import webpush from "web-push";
import { sendCallFcm } from "../config/fcm.js";
import "../config/env.js";
import {
  pool, USERS_TABLE, CHATS_TABLE, MESSAGES_TABLE,
  BLOCKED_USERS_TABLE,
} from "../config/database.js";

// Web Push VAPID sozlash
if (process.env.VAPID_PUBLIC_KEY && process.env.VAPID_PRIVATE_KEY) {
  webpush.setVapidDetails(
    "mailto:noreply@bootchat.com",
    process.env.VAPID_PUBLIC_KEY,
    process.env.VAPID_PRIVATE_KEY
  );
}

const browsers = [];
const onlineUsers = new Map(); // username -> Set of sockets
const lastActiveTime = new Map();
const activeCalls = new Map(); // callId -> session
const activeCallByUser = new Map(); // username -> callId
const pendingOfflineTimeouts = new Map(); // username -> timeout
const pendingCallOffers = new Map(); // username -> { payload, timeout }

const CALL_RESUME_GRACE_MS = Number(process.env.CALL_RESUME_GRACE_MS || 45000);
const PRESENCE_OFFLINE_GRACE_MS = Number(process.env.PRESENCE_OFFLINE_GRACE_MS || 60000);
const CALL_OFFER_DELIVERY_GRACE_MS = Number(process.env.CALL_OFFER_DELIVERY_GRACE_MS || 60000);

// --- YORDAMCHI FUNKSIYALAR ---

function hasLiveSockets(username) {
  const sockets = onlineUsers.get(username);
  return Boolean(sockets && sockets.size > 0);
}

function emitToUser(username, event, data) {
  const sockets = onlineUsers.get(username);
  if (!sockets || sockets.size === 0) return false;
  let delivered = false;
  for (const s of sockets) {
    if (s.connected) {
      s.emit(event, data);
      delivered = true;
    }
  }
  return delivered;
}

async function sendPushToUser(username, notification) {
  if (!username || !notification) return;
  if (!process.env.VAPID_PUBLIC_KEY || !process.env.VAPID_PRIVATE_KEY) return;

  try {
    const userResult = await pool.query(
      `SELECT id FROM ${USERS_TABLE} WHERE username = $1`,
      [username]
    );
    if (userResult.rowCount === 0) return;

    const userId = userResult.rows[0].id;
    const subscriptionResult = await pool.query(
      `SELECT endpoint, p256dh, auth FROM push_subscriptions WHERE user_id = $1`,
      [userId]
    );

    if (subscriptionResult.rowCount === 0) return;

    const payload = JSON.stringify(notification);
    await Promise.allSettled(
      subscriptionResult.rows.map(async (subscription) => {
        try {
          await webpush.sendNotification(
            {
              endpoint: subscription.endpoint,
              keys: {
                p256dh: subscription.p256dh,
                auth: subscription.auth,
              },
            },
            payload
          );
        } catch (error) {
          const statusCode = error?.statusCode;
          if (statusCode === 404 || statusCode === 410) {
            await pool.query(
              "DELETE FROM push_subscriptions WHERE endpoint = $1",
              [subscription.endpoint]
            );
            return;
          }
          console.error("Push yuborishda xato:", error);
        }
      })
    );
  } catch (error) {
    console.error("sendPushToUser xato:", error);
  }
}

async function sendFcmCallToUser(username, data) {
  try {
    const res = await pool.query('SELECT token FROM fcm_tokens WHERE username = $1', [username]);
    if (res.rowCount === 0) return;
    const result = await sendCallFcm(res.rows[0].token, data);
    if (result === 'expired') {
      await pool.query('DELETE FROM fcm_tokens WHERE username = $1', [username]);
    }
  } catch (e) {
    console.error('[FCM] sendFcmCallToUser error:', e.message);
  }
}

function finalizeCallSession(callId) {
  const call = activeCalls.get(callId);
  if (!call) return null;
  activeCallByUser.delete(call.caller);
  activeCallByUser.delete(call.callee);
  activeCalls.delete(callId);
  return call;
}

// --- ASOSIY HANDLER ---

function registerSocketHandlers(io) {
  io.on("connection", (browser) => {
    browsers.push(browser);

    browser.on("USER_ONLINE", (username) => {
      if (!username) return;
      browser.username = username;

      // Offline timeoutni tozalash
      const timeout = pendingOfflineTimeouts.get(username);
      if (timeout) {
        clearTimeout(timeout);
        pendingOfflineTimeouts.delete(username);
      }

      if (!onlineUsers.has(username)) onlineUsers.set(username, new Set());
      onlineUsers.get(username).add(browser);

      // DB ga online holatini saqlash
      pool.query(`UPDATE ${USERS_TABLE} SET is_online = TRUE WHERE username = $1`, [username])
        .catch(e => console.error('is_online true xato:', e.message));

      sendAllUsers();
      browser.broadcast.emit("USER_STATUS_CHANGED", { username, online: true });

      // Pending offer bor bo'lsa — faqat CALL_OFFER yuboramiz, CALL_SESSION_SYNC emas.
      // Aks holda ikkalasi bir vaqtda kelsa Flutter CALL_OFFER ni reject qilib yuboradi.
      const pending = pendingCallOffers.get(username);
      if (pending) {
        browser.emit("CALL_OFFER", pending.payload);
        for (const cand of pending.candidates || []) {
          browser.emit("ICE_CANDIDATE", { candidate: cand, callId: pending.payload.callId });
        }
        clearTimeout(pending.timeout);
        pendingCallOffers.delete(username);
      } else {
        // Pending yo'q — Call Resume (qo'ng'iroq davom etayotgan, socket uzilgan holat)
        const activeCall = activeCallByUser.get(username);
        if (activeCall) {
          const session = activeCalls.get(activeCall);
          if (session) {
            const peerUsername = session.caller === username ? session.callee : session.caller;
            const peerInfo = session.participants[peerUsername] || { username: peerUsername };
            const syncPayload = {
              callId: session.id,
              isVideo: session.isVideo,
              status: session.status,
              peer: peerInfo,
              direction: session.caller === username ? "outgoing" : "incoming"
            };
            if (session.caller !== username && session.status === "ringing" && session.offer) {
              syncPayload.offer = session.offer;
            }
            browser.emit("CALL_SESSION_SYNC", syncPayload);
          }
        }
      }
    });

    // --- VIDEO CALL SIGNALING ---

    browser.on("CALL_OFFER", async (data) => {
      const { target, offer, isVideo, caller } = data;
      const callerUsername = browser.username;
      if (!callerUsername || !target) return;

      const callId = data.callId || `call_${Date.now()}_${callerUsername}`;

      // Avvalgi pending call uchun eski timeoutni tozalash (retry case)
      const existingPending = pendingCallOffers.get(target);
      if (existingPending) {
        clearTimeout(existingPending.timeout);
        pendingCallOffers.delete(target);
      }

      // Sessiyani saqlash
      const session = {
        id: callId,
        caller: callerUsername,
        callee: target,
        isVideo: !!isVideo,
        status: "ringing",
        offer,
        participants: { [callerUsername]: caller }
      };
      activeCalls.set(callId, session);
      activeCallByUser.set(callerUsername, callId);
      activeCallByUser.set(target, callId);

      const delivered = emitToUser(target, "CALL_OFFER", { callId, caller, offer, isVideo });

      // FCM faqat socket yetkazolmagan holatda yuboriladi.
      // App foregroundda bo'lsa socket yetkazadi — FCM yuborilsa ikki xil notification chiqadi.
      if (!delivered) {
        sendFcmCallToUser(target, {
          callerName: callerUsername,
          isVideo: !!isVideo,
          callId,
        });
      }

      if (!delivered) {
        const timeout = setTimeout(() => {
          if (pendingCallOffers.has(target)) {
            pendingCallOffers.delete(target);
            finalizeCallSession(callId);
            emitToUser(callerUsername, "CALL_NOT_DELIVERED", { target });
            sendPushToUser(target, {
              title: callerUsername,
              body: isVideo ? "Video qo'ng'iroq..." : "Ovozli qo'ng'iroq...",
              tag: "call_" + callerUsername,
            });
          }
        }, CALL_OFFER_DELIVERY_GRACE_MS);

        pendingCallOffers.set(target, { payload: { callId, caller, offer, isVideo }, candidates: [], timeout });
      }
    });

    browser.on("CALL_ANSWER", (data) => {
      const { target, answer, callId } = data;
      const session = activeCalls.get(callId);
      if (session) {
        session.status = "connected";
        session.connectedAt = Date.now();
      }
      emitToUser(target, "CALL_ANSWER", { answer, callId, answeredAt: Date.now() });
    });

    browser.on("CALL_CONNECTED", (data) => {
      const { target, callId } = data;
      const connectedAt = Date.now();
      const session = activeCalls.get(callId);
      if (session) {
        session.status = "connected";
        session.connectedAt = session.connectedAt || connectedAt;
      }
      emitToUser(target, "CALL_CONNECTED", { callId, connectedAt });
    });

    browser.on("ICE_CANDIDATE", (data) => {
      const { target, candidate, callId } = data;
      if (!target) return;
      const delivered = emitToUser(target, "ICE_CANDIDATE", { candidate, callId });
      if (!delivered) {
        // Target offline — pending offer bilan birga saqlab qo'yamiz
        const pending = pendingCallOffers.get(target);
        if (pending && pending.payload.callId === callId) {
          pending.candidates.push(candidate);
        }
      }
    });

    browser.on("CALL_REJECT", (data) => {
      const { target, callId } = data;
      emitToUser(target, "CALL_REJECT", { callId });
      finalizeCallSession(callId);
    });

    browser.on("CALL_END", (data) => {
      const { target, callId } = data;
      emitToUser(target, "CALL_END", { callId });
      // Caller hang up qilsa pending offerini ham tozalash
      const pending = pendingCallOffers.get(target);
      if (pending && pending.payload.callId === callId) {
        clearTimeout(pending.timeout);
        pendingCallOffers.delete(target);
      }
      const session = finalizeCallSession(callId);
      if (session) {
        // Server tomonida hisoblash — client yuborgan duration ishonchsiz
        const serverDuration = session.connectedAt
          ? Math.round((Date.now() - session.connectedAt) / 1000)
          : 0;
        const duration = serverDuration > 0 ? serverDuration : (data.duration || 0);
        saveCallMessage(session.caller, session.callee, session.isVideo, duration);
      }
    });

    browser.on("CALL_RENEGOTIATE", (data) => {
      const { target, offer, callId, isVideo } = data;
      if (target) emitToUser(target, "CALL_RENEGOTIATE", { offer, callId, isVideo });
    });

    browser.on("CALL_RENEGOTIATE_ANSWER", (data) => {
      const { target, answer, callId } = data;
      if (target) emitToUser(target, "CALL_RENEGOTIATE_ANSWER", { answer, callId });
    });

    browser.on("NEW_MESSAGE", async (data) => {
      const senderUsername = browser.username;
      if (!senderUsername) return;
      const { receiver, message = "", image, audio, video, replyTo, persisted, id: persistedId, created_at: persistedAt, avatar: clientAvatar } = data || {};
      if (!receiver) return;
      try {
        // Web frontend REST API orqali allaqachon saqlagan — faqat receiverga yetkazish
        if (persisted && persistedId) {
          const senderRes = await pool.query(
            `SELECT username, avatar, full_name FROM ${USERS_TABLE} WHERE username = $1`, [senderUsername]
          );
          if (senderRes.rowCount === 0) return;
          const sender = senderRes.rows[0];
          const text = typeof message === "string" ? message.trim() : "";
          const payload = {
            id: persistedId,
            created_at: persistedAt,
            user: sender.username,
            username: sender.username,
            full_name: sender.full_name,
            avatar: sender.avatar || clientAvatar,
            receiver,
            content: text,
            message: text,
            image: image || null,
            audio: audio || null,
            video: video || null,
            reply_to_username: replyTo?.username || null,
            reply_to_content: replyTo?.content || null,
          };
          emitToUser(receiver, "NEW_MESSAGE", payload);
          return;
        }

        // Flutter / REST-siz: DB ga saqla, sender ga echo qaytarsin
        const [senderRes, receiverRes] = await Promise.all([
          pool.query(`SELECT id, username, avatar, full_name FROM ${USERS_TABLE} WHERE username = $1`, [senderUsername]),
          pool.query(`SELECT id FROM ${USERS_TABLE} WHERE username = $1`, [receiver]),
        ]);
        if (senderRes.rowCount === 0 || receiverRes.rowCount === 0) return;
        const sender = senderRes.rows[0];
        const senderId = sender.id;
        const receiverId = receiverRes.rows[0].id;
        const [u1, u2] = senderId < receiverId ? [senderId, receiverId] : [receiverId, senderId];
        let chatResult = await pool.query(
          `SELECT id FROM ${CHATS_TABLE} WHERE user1_id = $1 AND user2_id = $2`, [u1, u2]
        );
        let chatId;
        if (chatResult.rowCount === 0) {
          const nc = await pool.query(
            `INSERT INTO ${CHATS_TABLE} (user1_id, user2_id) VALUES ($1, $2) RETURNING id`, [u1, u2]
          );
          chatId = nc.rows[0].id;
        } else {
          chatId = chatResult.rows[0].id;
        }
        const text = typeof message === "string" ? message.trim() : "";
        const msgResult = await pool.query(
          `INSERT INTO ${MESSAGES_TABLE} (chat_id, sender_id, content, image, audio, video, reply_to_username, reply_to_content)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING id, created_at, is_read`,
          [chatId, senderId, text, image || null, audio || null, video || null,
           replyTo?.username || null, replyTo?.content || null]
        );
        const saved = {
          id: msgResult.rows[0].id,
          created_at: msgResult.rows[0].created_at,
          is_read: msgResult.rows[0].is_read,
          user: sender.username,
          username: sender.username,
          full_name: sender.full_name,
          avatar: sender.avatar,
          receiver,
          content: text,
          message: text,
          image: image || null,
          audio: audio || null,
          video: video || null,
          reply_to_username: replyTo?.username || null,
          reply_to_content: replyTo?.content || null,
        };
        emitToUser(receiver, "NEW_MESSAGE", saved);
        browser.emit("NEW_MESSAGE", saved);
      } catch (err) {
        console.error("NEW_MESSAGE socket error:", err);
      }
    });

    browser.on("MESSAGES_READ", async (data) => {
      const { chatWith } = data || {};
      const username = browser.username;
      if (!username || !chatWith) return;
      try {
        const [userRes, peerRes] = await Promise.all([
          pool.query(`SELECT id FROM ${USERS_TABLE} WHERE username = $1`, [username]),
          pool.query(`SELECT id FROM ${USERS_TABLE} WHERE username = $1`, [chatWith]),
        ]);
        if (userRes.rowCount === 0 || peerRes.rowCount === 0) return;
        const userId = userRes.rows[0].id;
        const peerId = peerRes.rows[0].id;
        const [u1, u2] = userId < peerId ? [userId, peerId] : [peerId, userId];
        const chatRes = await pool.query(
          `SELECT id FROM ${CHATS_TABLE} WHERE user1_id = $1 AND user2_id = $2`, [u1, u2]
        );
        if (chatRes.rowCount === 0) return;
        await pool.query(
          `UPDATE ${MESSAGES_TABLE} SET is_read = TRUE, read_at = NOW()
           WHERE chat_id = $1 AND sender_id = $2 AND COALESCE(is_read, FALSE) = FALSE`,
          [chatRes.rows[0].id, peerId]
        );
        emitToUser(chatWith, "MESSAGES_READ", { by: username });
      } catch (err) {
        console.error("MESSAGES_READ error:", err);
      }
    });

    browser.on("disconnect", () => {
      const username = browser.username;
      const index = browsers.indexOf(browser);
      if (index > -1) browsers.splice(index, 1);

      if (username && onlineUsers.has(username)) {
        const sockets = onlineUsers.get(username);
        sockets.delete(browser);

        if (sockets.size === 0) {
          // Flutter backgroundga o'tganda darrov oflayn qilmaslik
          const timeout = setTimeout(async () => {
            onlineUsers.delete(username);
            const lastActive = new Date().toISOString();
            try {
              await pool.query(
                `UPDATE ${USERS_TABLE} SET last_seen = NOW(), is_online = FALSE WHERE username = $1`,
                [username]
              );
            } catch (e) {
              console.error("last_seen yangilashda xato:", e);
            }
            sendAllUsers();
            io.emit("USER_STATUS_CHANGED", { username, online: false, lastActive });
          }, PRESENCE_OFFLINE_GRACE_MS);
          pendingOfflineTimeouts.set(username, timeout);
        }
      }
    });
  });
}

async function saveCallMessage(caller, target, isVideo, duration) {
  try {
    const type = isVideo ? "video" : "audio";
    const content = duration > 0 ? `__CALL:${type}:${duration}__` : `__CALL:${type}:missed__`;
    const [callerRes, targetRes] = await Promise.all([
      pool.query(`SELECT id FROM ${USERS_TABLE} WHERE username = $1`, [caller]),
      pool.query(`SELECT id FROM ${USERS_TABLE} WHERE username = $1`, [target]),
    ]);
    if (callerRes.rowCount === 0 || targetRes.rowCount === 0) return;
    const callerId = callerRes.rows[0].id;
    const targetId = targetRes.rows[0].id;
    const [u1, u2] = callerId < targetId ? [callerId, targetId] : [targetId, callerId];
    let chatResult = await pool.query(
      `SELECT id FROM ${CHATS_TABLE} WHERE user1_id = $1 AND user2_id = $2`, [u1, u2]
    );
    let chatId;
    if (chatResult.rowCount === 0) {
      const nc = await pool.query(
        `INSERT INTO ${CHATS_TABLE} (user1_id, user2_id) VALUES ($1, $2) RETURNING id`, [u1, u2]
      );
      chatId = nc.rows[0].id;
    } else {
      chatId = chatResult.rows[0].id;
    }
    const msgResult = await pool.query(
      `INSERT INTO ${MESSAGES_TABLE} (chat_id, sender_id, content) VALUES ($1, $2, $3) RETURNING id, created_at`,
      [chatId, callerId, content]
    );
    // Update last_seen for both caller and callee
    await pool.query(
      `UPDATE ${USERS_TABLE} SET last_seen = NOW() WHERE id = ANY($1::int[])`,
      [[callerId, targetId]]
    );
    // Ikki tarafga ham real-time bildiramiz — refresh kerak emas
    const callMsg = {
      id: msgResult.rows[0].id,
      created_at: msgResult.rows[0].created_at,
      user: caller,
      username: caller,
      receiver: target,
      content,
      message: content,
      image: null,
      audio: null,
      video: null,
    };
    emitToUser(caller, "NEW_MESSAGE", callMsg);
    emitToUser(target, "NEW_MESSAGE", callMsg);
  } catch (e) { console.error("Call log error", e); }
}

async function sendAllUsers() {
  const list = Array.from(onlineUsers.keys())
    .filter(u => hasLiveSockets(u))
    .map(u => ({ username: u, online: true }));
  for (const [, sockets] of onlineUsers) {
    for (const s of sockets) {
      if (s.connected) s.emit("ONLINE_USERS_LIST", list);
    }
  }
}

export { registerSocketHandlers };
