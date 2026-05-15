import webpush from "web-push";
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
const CALL_OFFER_DELIVERY_GRACE_MS = Number(process.env.CALL_OFFER_DELIVERY_GRACE_MS || 30000);

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

      sendAllUsers();
      browser.broadcast.emit("USER_STATUS_CHANGED", { username, online: true });

      // Call Resume (Flutter reconnect bo'lganda qo'ng'iroqni tiklash)
      const activeCall = activeCallByUser.get(username);
      if (activeCall) {
        const session = activeCalls.get(activeCall);
        if (session) {
          const peerUsername = session.caller === username ? session.callee : session.caller;
          const peerInfo = session.participants[peerUsername] || { username: peerUsername };
          
          browser.emit("CALL_SESSION_SYNC", {
            callId: session.id,
            isVideo: session.isVideo,
            status: session.status,
            peer: peerInfo,
            direction: session.caller === username ? "outgoing" : "incoming"
          });
        }
      }

      // Kutilayotgan takliflar (Push notificationdan so'ng appga kirganda)
      const pending = pendingCallOffers.get(username);
      if (pending) {
        browser.emit("CALL_OFFER", pending.payload);
        clearTimeout(pending.timeout);
        pendingCallOffers.delete(username);
      }
    });

    // --- VIDEO CALL SIGNALING ---

    browser.on("CALL_OFFER", async (data) => {
      const { target, offer, isVideo, caller } = data;
      const callerUsername = browser.username;
      if (!callerUsername || !target) return;

      const callId = data.callId || `call_${Date.now()}_${callerUsername}`;
      
      // Sessiyani saqlash
      const session = {
        id: callId,
        caller: callerUsername,
        callee: target,
        isVideo: !!isVideo,
        status: "ringing",
        participants: { [callerUsername]: caller }
      };
      activeCalls.set(callId, session);
      activeCallByUser.set(callerUsername, callId);
      activeCallByUser.set(target, callId);

      const delivered = emitToUser(target, "CALL_OFFER", { callId, caller, offer, isVideo });

      if (!delivered) {
        // Flutter backgroundda bo'lsa yoki oflayn bo'lsa
        const timeout = setTimeout(() => {
          if (pendingCallOffers.has(target)) {
            pendingCallOffers.delete(target);
            finalizeCallSession(callId);
            emitToUser(callerUsername, "CALL_NOT_DELIVERED", { target });
            sendPushToUser(target, { 
              title: callerUsername, 
              body: isVideo ? "Video qo'ng'iroq..." : "Ovozli qo'ng'iroq...",
              tag: "call_" + callerUsername 
            });
          }
        }, CALL_OFFER_DELIVERY_GRACE_MS);

        pendingCallOffers.set(target, { payload: { callId, caller, offer, isVideo }, timeout });
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
      if (target) emitToUser(target, "ICE_CANDIDATE", { candidate, callId });
    });

    browser.on("CALL_REJECT", (data) => {
      const { target, callId } = data;
      emitToUser(target, "CALL_REJECT", { callId });
      finalizeCallSession(callId);
    });

    browser.on("CALL_END", (data) => {
      const { target, callId } = data;
      emitToUser(target, "CALL_END", { callId });
      const session = finalizeCallSession(callId);
      if (session) {
        saveCallMessage(session.caller, session.callee, session.isVideo, data.duration || 0);
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
          const timeout = setTimeout(() => {
            onlineUsers.delete(username);
            sendAllUsers();
            io.emit("USER_STATUS_CHANGED", { username, online: false });
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
    await pool.query(
      `INSERT INTO ${MESSAGES_TABLE} (chat_id, sender_id, content) VALUES ($1, $2, $3)`,
      [chatId, callerId, content]
    );
  } catch (e) { console.error("Call log error", e); }
}

async function sendAllUsers() {
  const list = Array.from(onlineUsers.keys()).map(u => ({ username: u, online: true }));
  for (const [, sockets] of onlineUsers) {
    for (const s of sockets) {
      if (s.connected) s.emit("ONLINE_USERS_LIST", list);
    }
  }
}

export { registerSocketHandlers };
