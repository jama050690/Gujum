import webpush from "web-push";
import "../config/env.js";
import {
  pool, USERS_TABLE, CHATS_TABLE, MESSAGES_TABLE,
  GROUPS_TABLE, GROUP_MEMBERS_TABLE, GROUP_MESSAGES_TABLE,
  CHANNELS_TABLE, CHANNEL_SUBSCRIBERS_TABLE, CHANNEL_MESSAGES_TABLE,
  BLOCKED_USERS_TABLE,
  FRIENDS_TABLE,
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
const CALL_RESUME_GRACE_MS = Number(process.env.CALL_RESUME_GRACE_MS || 45000);
const PRESENCE_OFFLINE_GRACE_MS = Number(process.env.PRESENCE_OFFLINE_GRACE_MS || 15000);
const pendingOfflineTimeouts = new Map(); // username -> timeout
const pendingCallOffers = new Map(); // username -> { payload, callerUsername, isVideo, createdAt, timeout }
const CALL_OFFER_DELIVERY_GRACE_MS = Number(process.env.CALL_OFFER_DELIVERY_GRACE_MS || 15000);

function hasLiveSockets(username) {
  const sockets = onlineUsers.get(username);
  return Boolean(sockets && sockets.size > 0);
}

function isPresenceGraceActive(username) {
  return pendingOfflineTimeouts.has(username);
}

function clearPendingOfflineTimeout(username) {
  const timeout = pendingOfflineTimeouts.get(username);
  if (timeout) {
    clearTimeout(timeout);
    pendingOfflineTimeouts.delete(username);
  }
}

function consumePendingCallOffer(username) {
  const pending = pendingCallOffers.get(username) || null;
  if (pending) {
    if (pending.timeout) {
      clearTimeout(pending.timeout);
    }
    pendingCallOffers.delete(username);
  }
  return pending;
}

function clearPendingCallOfferByCallId(callId) {
  for (const [username, pending] of pendingCallOffers.entries()) {
    if (pending?.payload?.callId === callId) {
      if (pending.timeout) {
        clearTimeout(pending.timeout);
      }
      pendingCallOffers.delete(username);
    }
  }
}

function getCallPeer(call, username) {
  if (!call || !username) return null;
  if (call.caller === username) return call.callee;
  if (call.callee === username) return call.caller;
  return null;
}

function clearUserActiveCall(username, callId) {
  if (activeCallByUser.get(username) === callId) {
    activeCallByUser.delete(username);
  }
}

function clearReconnectTimer(call, username) {
  const timer = call?.disconnectTimers?.get(username);
  if (timer) {
    clearTimeout(timer);
    call.disconnectTimers.delete(username);
  }
  call?.reconnectingUsers?.delete(username);
}

function finalizeCallSession(callId) {
  const call = activeCalls.get(callId);
  if (!call) return null;

  for (const timer of call.disconnectTimers.values()) {
    clearTimeout(timer);
  }

  clearUserActiveCall(call.caller, callId);
  clearUserActiveCall(call.callee, callId);
  clearPendingCallOfferByCallId(callId);
  activeCalls.delete(callId);
  return call;
}

function upsertCallSession({ callId, caller, callee, isVideo, callerInfo = null }) {
  const existing = activeCalls.get(callId);
  const session = existing || {
    id: callId,
    caller,
    callee,
    isVideo: Boolean(isVideo),
    status: "ringing",
    createdAt: Date.now(),
    participants: {},
    latestOffer: null,
    disconnectTimers: new Map(),
    reconnectingUsers: new Set(),
  };

  session.caller = caller;
  session.callee = callee;
  session.isVideo = Boolean(isVideo);
  session.status = session.status || "ringing";
  session.participants = session.participants || {};
  session.latestOffer = session.latestOffer || null;
  session.disconnectTimers = session.disconnectTimers || new Map();
  session.reconnectingUsers = session.reconnectingUsers || new Set();

  if (callerInfo) {
    session.participants[caller] = {
      username: caller,
      avatar: callerInfo.avatar || null,
      full_name: callerInfo.full_name || null,
    };
  } else if (!session.participants[caller]) {
    session.participants[caller] = { username: caller, avatar: null, full_name: null };
  }

  if (!session.participants[callee]) {
    session.participants[callee] = { username: callee, avatar: null, full_name: null };
  }

  activeCalls.set(callId, session);
  activeCallByUser.set(caller, callId);
  activeCallByUser.set(callee, callId);
  return session;
}

function getUserActiveCall(username) {
  const callId = activeCallByUser.get(username);
  if (!callId) return null;

  const call = activeCalls.get(callId);
  if (!call) {
    activeCallByUser.delete(username);
    return null;
  }

  return call;
}

function buildCallSessionPayload(call, username) {
  const peerUsername = getCallPeer(call, username);
  const peerInfo = call?.participants?.[peerUsername] || { username: peerUsername };

  return {
    callId: call.id,
    isVideo: Boolean(call.isVideo),
    status: call.status || "ringing",
    startedAt: call.connectedAt || null,
    direction: call.caller === username ? "outgoing" : "incoming",
    peer: {
      username: peerUsername,
      avatar: peerInfo.avatar || null,
      full_name: peerInfo.full_name || null,
    },
  };
}

// Username ga tegishli barcha socketlarga emit qilish
function emitToUser(username, event, data) {
  const sockets = onlineUsers.get(username);
  if (!sockets || sockets.size === 0) return false;
  for (const s of sockets) {
    s.emit(event, data);
  }
  return true;
}

// Offline foydalanuvchiga push notification yuborish
async function sendPushToUser(username, payload) {
  try {
    const result = await pool.query(
      `SELECT ps.endpoint, ps.p256dh, ps.auth, ps.id
       FROM push_subscriptions ps
       JOIN users u ON ps.user_id = u.id
       WHERE u.username = $1`,
      [username]
    );

    for (const sub of result.rows) {
      const pushSubscription = {
        endpoint: sub.endpoint,
        keys: { p256dh: sub.p256dh, auth: sub.auth },
      };
      try {
        await webpush.sendNotification(pushSubscription, JSON.stringify(payload));
      } catch (err) {
        if (err.statusCode === 410 || err.statusCode === 404) {
          // Subscription eskirgan — o'chirish
          await pool.query("DELETE FROM push_subscriptions WHERE id = $1", [sub.id]);
        }
      }
    }
  } catch (err) {
    console.error("Push notification yuborishda xato:", err);
  }
}

async function isBlocked(username1, username2) {
  try {
    const result = await pool.query(
      `SELECT 1 FROM ${BLOCKED_USERS_TABLE} b
       JOIN ${USERS_TABLE} u1 ON b.blocker_id = u1.id
       JOIN ${USERS_TABLE} u2 ON b.blocked_id = u2.id
       WHERE (u1.username = $1 AND u2.username = $2)
          OR (u1.username = $2 AND u2.username = $1)
       LIMIT 1`,
      [username1, username2]
    );
    return result.rowCount > 0;
  } catch {
    return false;
  }
}

async function sendAllUsers(targetBrowser = null) {
  try {
    const { rows } = await pool.query(
      `SELECT id, username, avatar, full_name, last_seen FROM users`
    );
    const usersList = rows.map(u => ({
      id: u.id,
      username: u.username,
      avatar: u.avatar,
      full_name: u.full_name || null,
      online: hasLiveSockets(u.username) || isPresenceGraceActive(u.username),
      lastActive: lastActiveTime.get(u.username) || (u.last_seen ? new Date(u.last_seen).getTime() : null)
    }));

    if (targetBrowser) {
      targetBrowser.emit("ONLINE_USERS_LIST", usersList);
    } else {
      for (const b of browsers) {
        b.emit("ONLINE_USERS_LIST", usersList);
      }
    }
  } catch (err) {
    console.error("Userlarni olishda xato:", err);
  }
}

function registerSocketHandlers(io) {
  io.on("connection", (browser) => {
    browsers.push(browser);
    console.log("foydalanuvchi ulandi");

    const sendActiveCallSync = (targetSocket, username) => {
      const call = getUserActiveCall(username);
      if (!call) return false;

      clearReconnectTimer(call, username);
      targetSocket.emit("CALL_SESSION_SYNC", buildCallSessionPayload(call, username));
      return true;
    };

    sendAllUsers(browser);

    browser.on("USER_ONLINE", (username) => {
      if (!username) return;

      browser.username = username;
      clearPendingOfflineTimeout(username);

      if (!onlineUsers.has(username)) {
        onlineUsers.set(username, new Set());
      }
      onlineUsers.get(username).add(browser);
      console.log(`${username} online bo'ldi (${onlineUsers.get(username).size} ta tab)`);

      sendAllUsers();

      browser.broadcast.emit("USER_STATUS_CHANGED", { username, online: true });

      const activeCall = getUserActiveCall(username);
      if (activeCall) {
        clearReconnectTimer(activeCall, username);
        const isIncomingRinging =
          activeCall.status !== "connected" &&
          activeCall.callee === username &&
          activeCall.latestOffer;

        if (isIncomingRinging) {
          browser.emit("CALL_OFFER", {
            callId: activeCall.id,
            caller: activeCall.participants[activeCall.caller] || { username: activeCall.caller },
            offer: activeCall.latestOffer,
            isVideo: Boolean(activeCall.isVideo),
            resume: false,
          });
        } else {
          browser.emit("CALL_SESSION_SYNC", buildCallSessionPayload(activeCall, username));
        }

        const peerUsername = getCallPeer(activeCall, username);
        if (activeCall.status === "connected" && peerUsername && onlineUsers.has(peerUsername)) {
          emitToUser(peerUsername, "CALL_PARTICIPANT_REJOINED", {
            callId: activeCall.id,
            username,
          });
        }
      }

      const pendingOffer = consumePendingCallOffer(username);
      if (pendingOffer) {
        const delivered = emitToUser(username, "CALL_OFFER", pendingOffer.payload);
        if (!delivered) {
          pendingCallOffers.set(username, pendingOffer);
        }
      }
    });

    browser.on("CALL_SESSION_SYNC_REQUEST", ({ username, callId } = {}) => {
      if (!username) return;
      const activeCall = getUserActiveCall(username);
      if (!activeCall) return;
      if (callId && activeCall.id !== callId) return;
      sendActiveCallSync(browser, username);
    });

    browser.on("NEW_MESSAGE", async (data) => {
      console.log(data.user + "dan " + data.receiver + "ga xabar: ", data.message || data.image);

      lastActiveTime.set(data.user, Date.now());

      try {
        if (data.persisted && data.id) {
          const msgPayload = {
            ...data,
            message: data.message || data.content || "",
            created_at: data.created_at || new Date().toISOString(),
          };

          emitToUser(data.user, "NEW_MESSAGE", msgPayload);
          const delivered = emitToUser(data.receiver, "NEW_MESSAGE", msgPayload);

          if (!delivered) {
            sendPushToUser(data.receiver, {
              title: data.user,
              body:
                data.message ||
                (data.image
                  ? "Rasm yubordi"
                  : data.audio
                    ? "Ovozli xabar"
                    : data.video
                      ? "Video yubordi"
                      : "Yangi xabar"),
              tag: "msg-" + data.user,
            });
          }
          return;
        }

        // Bloklash tekshiruvi
        const blocked = await isBlocked(data.user, data.receiver);
        if (blocked) {
          emitToUser(data.user, "MESSAGE_BLOCKED", { receiver: data.receiver });
          return;
        }
        const senderResult = await pool.query(
          `SELECT id FROM ${USERS_TABLE} WHERE username = $1`,
          [data.user]
        );
        const receiverResult = await pool.query(
          `SELECT id FROM ${USERS_TABLE} WHERE username = $1`,
          [data.receiver]
        );

        if (senderResult.rowCount === 0 || receiverResult.rowCount === 0) {
          console.error("Sender yoki receiver topilmadi");
          return;
        }

        const senderId = senderResult.rows[0].id;
        const receiverId = receiverResult.rows[0].id;

        const [user1Id, user2Id] = senderId < receiverId
          ? [senderId, receiverId]
          : [receiverId, senderId];

        let chatResult = await pool.query(
          `SELECT id FROM ${CHATS_TABLE} WHERE user1_id = $1 AND user2_id = $2`,
          [user1Id, user2Id]
        );

        let chatId;
        if (chatResult.rowCount === 0) {
          const newChat = await pool.query(
            `INSERT INTO ${CHATS_TABLE} (user1_id, user2_id) VALUES ($1, $2) RETURNING id`,
            [user1Id, user2Id]
          );
          chatId = newChat.rows[0].id;
        } else {
          chatId = chatResult.rows[0].id;
        }

        const msgResult = await pool.query(
          `INSERT INTO ${MESSAGES_TABLE} (chat_id, sender_id, content, image, audio, video, reply_to_username, reply_to_content) VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING id, created_at`,
          [
            chatId,
            senderId,
            data.message || "",
            data.image || null,
            data.audio || null,
            data.video || null,
            data.replyTo?.username || null,
            data.replyTo?.content || null,
          ],
        );

        const msgPayload = { ...data, id: msgResult.rows[0].id, created_at: msgResult.rows[0].created_at };
        emitToUser(data.user, "NEW_MESSAGE", msgPayload);
        const delivered = emitToUser(data.receiver, "NEW_MESSAGE", msgPayload);

        // Receiver offline bo'lsa push notification yuborish
        if (!delivered) {
          sendPushToUser(data.receiver, {
            title: data.user,
            body:
              data.message ||
              (data.image
                ? "Rasm yubordi"
                : data.audio
                  ? "Ovozli xabar"
                  : data.video
                    ? "Video yubordi"
                    : "Yangi xabar"),
            tag: "msg-" + data.user,
          });
        }
      } catch (err) {
        console.error("Xabar saqlashda xato:", err);
      }
    });

    // ==================
    // Group Messages
    // ==================
    browser.on("GROUP_MESSAGE", async (data) => {
      const { groupId, user: senderUsername, message, image, audio, avatar } = data;
      console.log(`Guruh xabar: ${senderUsername} → group #${groupId}: ${message || image}`);

      lastActiveTime.set(senderUsername, Date.now());

      try {
        const senderResult = await pool.query(
          `SELECT id FROM ${USERS_TABLE} WHERE username = $1`,
          [senderUsername]
        );
        if (senderResult.rowCount === 0) return;

        const senderId = senderResult.rows[0].id;

        const msgResult = await pool.query(
          `INSERT INTO ${GROUP_MESSAGES_TABLE} (group_id, sender_id, content, image, audio) VALUES ($1, $2, $3, $4, $5) RETURNING id, created_at`,
          [groupId, senderId, message || "", image || null, audio || null]
        );

        const payload = {
          id: msgResult.rows[0].id,
          groupId,
          username: senderUsername,
          avatar,
          content: message || "",
          image: image || null,
          audio: audio || null,
          created_at: msgResult.rows[0].created_at,
        };

        const members = await pool.query(
          `SELECT u.username FROM ${GROUP_MEMBERS_TABLE} gm JOIN ${USERS_TABLE} u ON gm.user_id = u.id WHERE gm.group_id = $1`,
          [groupId]
        );

        for (const member of members.rows) {
          emitToUser(member.username, "GROUP_MESSAGE", payload);
        }
      } catch (err) {
        console.error("Guruh xabar saqlashda xato:", err);
      }
    });

    // ==================
    // Channel Messages
    // ==================
    browser.on("CHANNEL_MESSAGE", async (data) => {
      const { channelId, user: senderUsername, message, image, audio, avatar } = data;
      console.log(`Kanal xabar: ${senderUsername} → channel #${channelId}: ${message || image}`);

      lastActiveTime.set(senderUsername, Date.now());

      try {
        const senderResult = await pool.query(
          `SELECT id FROM ${USERS_TABLE} WHERE username = $1`,
          [senderUsername]
        );
        if (senderResult.rowCount === 0) return;

        const senderId = senderResult.rows[0].id;

        const msgResult = await pool.query(
          `INSERT INTO ${CHANNEL_MESSAGES_TABLE} (channel_id, sender_id, content, image, audio) VALUES ($1, $2, $3, $4, $5) RETURNING id, created_at`,
          [channelId, senderId, message || "", image || null, audio || null]
        );

        const payload = {
          id: msgResult.rows[0].id,
          channelId,
          username: senderUsername,
          avatar,
          content: message || "",
          image: image || null,
          audio: audio || null,
          created_at: msgResult.rows[0].created_at,
        };

        const subs = await pool.query(
          `SELECT u.username FROM ${CHANNEL_SUBSCRIBERS_TABLE} cs JOIN ${USERS_TABLE} u ON cs.user_id = u.id WHERE cs.channel_id = $1`,
          [channelId]
        );

        for (const sub of subs.rows) {
          emitToUser(sub.username, "CHANNEL_MESSAGE", payload);
        }
      } catch (err) {
        console.error("Kanal xabar saqlashda xato:", err);
      }
    });

    // Xabarlar o'qilganda senderga xabar berish
    browser.on("MESSAGES_READ", (data) => {
      const { reader, sender } = data;
      if (sender) {
        emitToUser(sender, "MESSAGES_READ", { reader, sender });
      }
    });

    browser.on("TYPING", (user) => {
      for (const b of browsers) {
        b.emit("TYPING", user);
      }
    });

    browser.on("MESSAGE_DELETED", (data) => {
      if (data.target) {
        emitToUser(data.target, "MESSAGE_DELETED", { messageId: data.messageId });
      }
    });

    // ==================
    // Friend Requests
    // ==================
    browser.on("FRIEND_REQUEST", async (data) => {
      const { targetUsername, senderUsername, senderAvatar } = data;
      emitToUser(targetUsername, "FRIEND_REQUEST", {
        username: senderUsername,
        avatar: senderAvatar,
      });
    });

    browser.on("FRIEND_ACCEPTED", async (data) => {
      const { targetUsername, accepterUsername, accepterAvatar } = data;
      emitToUser(targetUsername, "FRIEND_ACCEPTED", {
        username: accepterUsername,
        avatar: accepterAvatar,
      });
    });

    // ==================
    // WebRTC Signaling
    // ==================

    async function saveCallMessage(callerUsername, targetUsername, isVideo, duration) {
      try {
        const callerRes = await pool.query(`SELECT id FROM ${USERS_TABLE} WHERE username = $1`, [callerUsername]);
        const targetRes = await pool.query(`SELECT id FROM ${USERS_TABLE} WHERE username = $1`, [targetUsername]);
        if (callerRes.rowCount === 0 || targetRes.rowCount === 0) return;

        const callerId = callerRes.rows[0].id;
        const targetId = targetRes.rows[0].id;
        const [user1Id, user2Id] = callerId < targetId ? [callerId, targetId] : [targetId, callerId];

        let chatResult = await pool.query(
          `SELECT id FROM ${CHATS_TABLE} WHERE user1_id = $1 AND user2_id = $2`,
          [user1Id, user2Id]
        );
        let chatId;
        if (chatResult.rowCount === 0) {
          const newChat = await pool.query(
            `INSERT INTO ${CHATS_TABLE} (user1_id, user2_id) VALUES ($1, $2) RETURNING id`,
            [user1Id, user2Id]
          );
          chatId = newChat.rows[0].id;
        } else {
          chatId = chatResult.rows[0].id;
        }

        const type = isVideo ? "video" : "audio";
        const content = duration > 0 ? `__CALL:${type}:${duration}__` : `__CALL:${type}:missed__`;

        const msgResult = await pool.query(
          `INSERT INTO ${MESSAGES_TABLE} (chat_id, sender_id, content) VALUES ($1, $2, $3) RETURNING id, created_at`,
          [chatId, callerId, content]
        );

        const callMsg = {
          id: msgResult.rows[0].id,
          user: callerUsername,
          receiver: targetUsername,
          message: content,
          created_at: msgResult.rows[0].created_at,
        };

        emitToUser(callerUsername, "NEW_MESSAGE", callMsg);
        emitToUser(targetUsername, "NEW_MESSAGE", callMsg);
      } catch (err) {
        console.error("Call xabarini saqlashda xato:", err);
      }
    }

    function scheduleCallReconnectTimeout(callId, disconnectedUsername) {
      const activeCall = activeCalls.get(callId);
      if (!activeCall) return;

      clearReconnectTimer(activeCall, disconnectedUsername);
      activeCall.reconnectingUsers.add(disconnectedUsername);

      const timer = setTimeout(async () => {
        const currentCall = activeCalls.get(callId);
        if (!currentCall) return;

        const peerUsername = getCallPeer(currentCall, disconnectedUsername);
        const duration = currentCall.connectedAt
          ? Math.max(0, Math.round((Date.now() - currentCall.connectedAt) / 1000))
          : 0;

        if (peerUsername) {
          emitToUser(peerUsername, "CALL_END", {
            callId,
            reason: "disconnect_timeout",
          });
        }

        finalizeCallSession(callId);
        await saveCallMessage(currentCall.caller, currentCall.callee, currentCall.isVideo || false, duration);
      }, CALL_RESUME_GRACE_MS);

      activeCall.disconnectTimers.set(disconnectedUsername, timer);
    }

    browser.on("CALL_OFFER", async (data) => {
      const callId = data.callId || `${data.caller?.username || "call"}:${data.target}:${Date.now()}`;

      console.log(`CALL_OFFER keldi: ${data.caller?.username} → ${data.target}`);
      console.log(`Target online mi: ${onlineUsers.has(data.target)}, socketlar: ${onlineUsers.get(data.target)?.size || 0}`);

      // Bloklash tekshiruvi
      try {
        const blocked = await isBlocked(data.caller.username, data.target);
        if (blocked) {
          console.log(`Qo'ng'iroq bloklangan: ${data.caller.username} → ${data.target}`);
          emitToUser(data.caller.username, "CALL_BLOCKED", { target: data.target });
          return;
        }
      } catch (err) {
        console.error("isBlocked tekshiruvida xato:", err);
      }

      const session = upsertCallSession({
        callId,
        caller: data.caller.username,
        callee: data.target,
        isVideo: data.isVideo,
        callerInfo: data.caller,
      });
      session.latestOffer = data.offer;

      clearReconnectTimer(session, data.caller.username);
      clearReconnectTimer(session, data.target);

      const delivered = emitToUser(data.target, "CALL_OFFER", {
        callId,
        caller: data.caller,
        offer: data.offer,
        isVideo: data.isVideo,
        resume: Boolean(data.resume),
      });
      console.log(`Qo'ng'iroq: ${data.caller.username} → ${data.target}, yetkazildi: ${delivered}`);

      // Target offline bo'lsa callerga xabar berish + push notification
      if (!delivered) {
        const previousPending = consumePendingCallOffer(data.target);
        if (previousPending?.payload?.callId && previousPending.payload.callId !== callId) {
          finalizeCallSession(previousPending.payload.callId);
        }

        const pendingOffer = {
          callerUsername: data.caller.username,
          isVideo: Boolean(data.isVideo),
          createdAt: Date.now(),
          payload: {
            callId,
            caller: data.caller,
            offer: data.offer,
            isVideo: data.isVideo,
            resume: Boolean(data.resume),
          },
          timeout: null,
        };

        pendingOffer.timeout = setTimeout(() => {
          const latestPending = pendingCallOffers.get(data.target);
          if (!latestPending || latestPending.payload.callId !== callId) return;

          pendingCallOffers.delete(data.target);
          finalizeCallSession(callId);
          emitToUser(data.caller.username, "CALL_NOT_DELIVERED", { target: data.target });
          sendPushToUser(data.target, {
            title: data.caller.username,
            body: data.isVideo ? "Video qo'ng'iroq" : "Audio qo'ng'iroq",
            tag: "call-" + data.caller.username,
          });
          console.log(`Qo'ng'iroq yetkazilmadi (timeout): ${data.caller.username} → ${data.target}`);
        }, CALL_OFFER_DELIVERY_GRACE_MS);

        pendingCallOffers.set(data.target, pendingOffer);
        console.log(`Qo'ng'iroq navbatga qo'yildi: ${data.caller.username} → ${data.target}`);
        return;
      }
    });

    browser.on("CALL_ANSWER", (data) => {
      const activeCall = activeCalls.get(data.callId);
      if (activeCall) {
        activeCall.status = "connected";
        activeCall.connectedAt = activeCall.connectedAt || Date.now();
        if (data.user?.username) {
          activeCall.participants[data.user.username] = {
            username: data.user.username,
            avatar: data.user.avatar || null,
            full_name: data.user.full_name || null,
          };
        }
        clearReconnectTimer(activeCall, data.target);
        clearReconnectTimer(activeCall, browser.username);
      }

      emitToUser(data.target, "CALL_ANSWER", { answer: data.answer, callId: data.callId });
    });

    browser.on("ICE_CANDIDATE", (data) => {
      emitToUser(data.target, "ICE_CANDIDATE", { candidate: data.candidate, callId: data.callId });
    });

    browser.on("CALL_REJECT", async (data) => {
      emitToUser(data.target, "CALL_REJECT", { callId: data.callId });
      finalizeCallSession(data.callId);
      // Save missed call message — caller is target (the one who originally called)
      await saveCallMessage(data.target, browser.username, data.isVideo || false, 0);
      console.log(`Qo'ng'iroq rad etildi: ${data.target}`);
    });

    browser.on("CALL_END", async (data) => {
      emitToUser(data.target, "CALL_END", { callId: data.callId, reason: data.reason || "hangup" });
      const currentCall = finalizeCallSession(data.callId);
      // Save call message
      const callerUsername = data.callerUsername || browser.username;
      const otherUsername = data.target;
      const fallbackDuration = currentCall?.connectedAt
        ? Math.max(0, Math.round((Date.now() - currentCall.connectedAt) / 1000))
        : 0;
      await saveCallMessage(callerUsername, otherUsername, data.isVideo || false, data.duration || fallbackDuration);
      console.log(`Qo'ng'iroq tugatildi: ${data.target} (${data.duration || 0}s)`);
    });

    browser.on("disconnect", () => {
      const index = browsers.indexOf(browser);
      if (index > -1) {
        browsers.splice(index, 1);
      }

      if (browser.username) {
        const sockets = onlineUsers.get(browser.username);
        if (sockets) {
          sockets.delete(browser);
          if (sockets.size === 0) {
            const activeCall = getUserActiveCall(browser.username);

            clearPendingOfflineTimeout(browser.username);
            pendingOfflineTimeouts.set(
              browser.username,
              setTimeout(() => {
                pendingOfflineTimeouts.delete(browser.username);

                const currentSockets = onlineUsers.get(browser.username);
                if (currentSockets && currentSockets.size === 0) {
                  onlineUsers.delete(browser.username);
                }

                const now = Date.now();
                lastActiveTime.set(browser.username, now);
                pool.query(
                  `UPDATE ${USERS_TABLE} SET last_seen = NOW() WHERE username = $1`,
                  [browser.username]
                ).catch(err => console.error("last_seen yangilashda xato:", err));
                console.log(`${browser.username} offline bo'ldi`);

                sendAllUsers();

                for (const b of browsers) {
                  b.emit("USER_STATUS_CHANGED", { username: browser.username, online: false, lastActive: Date.now() });
                }

                // Pending call offers manage their own timeout and fallback delivery.
              }, PRESENCE_OFFLINE_GRACE_MS),
            );
            console.log(`${browser.username} reconnect kutilmoqda (${PRESENCE_OFFLINE_GRACE_MS}ms)`);

            sendAllUsers();

            if (activeCall?.status === "connected") {
              const peerUsername = getCallPeer(activeCall, browser.username);
              if (peerUsername) {
                emitToUser(peerUsername, "CALL_PARTICIPANT_RECONNECTING", {
                  callId: activeCall.id,
                  username: browser.username,
                  graceMs: CALL_RESUME_GRACE_MS,
                });
              }
              scheduleCallReconnectTimeout(activeCall.id, browser.username);
            }
          } else {
            console.log(`${browser.username} ning 1 ta tabi yopildi (hali ${sockets.size} ta tab ochiq)`);
          }
        }
      }
    });
  });
}

export { registerSocketHandlers };
