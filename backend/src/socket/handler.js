import webpush from "web-push";
import "../config/env.js";
import {
  pool, USERS_TABLE, CHATS_TABLE, MESSAGES_TABLE,
  GROUPS_TABLE, GROUP_MEMBERS_TABLE, GROUP_MESSAGES_TABLE,
  CHANNELS_TABLE, CHANNEL_SUBSCRIBERS_TABLE, CHANNEL_MESSAGES_TABLE,
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
const CALL_RESUME_GRACE_MS = Number(process.env.CALL_RESUME_GRACE_MS || 45000);
const PRESENCE_OFFLINE_GRACE_MS = Number(process.env.PRESENCE_OFFLINE_GRACE_MS || 60000);
const pendingOfflineTimeouts = new Map(); // username -> timeout
const pendingCallOffers = new Map(); // username -> { payload, callerUsername, isVideo, createdAt, timeout }
const CALL_OFFER_DELIVERY_GRACE_MS = Number(process.env.CALL_OFFER_DELIVERY_GRACE_MS || 30000);

// --- YORDAMCHI FUNKSIYALAR ---

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
    if (pending.timeout) clearTimeout(pending.timeout);
    pendingCallOffers.delete(username);
  }
  return pending;
}

function clearPendingCallOfferByCallId(callId) {
  for (const [username, pending] of pendingCallOffers.entries()) {
    if (pending?.payload?.callId === callId) {
      if (pending.timeout) clearTimeout(pending.timeout);
      pendingCallOffers.delete(username);
    }
  }
}

function getCallPeer(call, username) {
  if (!call || !username) return null;
  return call.caller === username ? call.callee : call.caller;
}

function isSameCallPair(call, usernameA, usernameB) {
  if (!call || !usernameA || !usernameB) return false;
  return (
    (call.caller === usernameA && call.callee === usernameB) ||
    (call.caller === usernameB && call.callee === usernameA)
  );
}

function getSharedActiveCall(usernameA, usernameB) {
  const firstId = activeCallByUser.get(usernameA);
  if (firstId) {
    const call = activeCalls.get(firstId);
    if (call && isSameCallPair(call, usernameA, usernameB)) return call;
  }
  const secondId = activeCallByUser.get(usernameB);
  if (secondId) {
    const call = activeCalls.get(secondId);
    if (call && isSameCallPair(call, usernameA, usernameB)) return call;
  }
  return null;
}

function finalizeCallSession(callId) {
  const call = activeCalls.get(callId);
  if (!call) return null;

  if (call.disconnectTimers) {
    for (const timer of call.disconnectTimers.values()) clearTimeout(timer);
  }

  activeCallByUser.delete(call.caller);
  activeCallByUser.delete(call.callee);
  clearPendingCallOfferByCallId(callId);
  activeCalls.delete(callId);
  return call;
}

function upsertCallSession({ callId, caller, callee, isVideo, callerInfo = null }) {
  let session = activeCalls.get(callId);
  if (!session) {
    session = {
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
  }

  if (callerInfo) {
    session.participants[caller] = {
      username: caller,
      avatar: callerInfo.avatar || null,
      full_name: callerInfo.full_name || null,
    };
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

async function sendPushToUser(username, payload) {
  try {
    const result = await pool.query(
      `SELECT ps.endpoint, ps.p256dh, ps.auth, ps.id FROM push_subscriptions ps
       JOIN users u ON ps.user_id = u.id WHERE u.username = $1`,
      [username]
    );
    for (const sub of result.rows) {
      const pushSubscription = { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } };
      try { await webpush.sendNotification(pushSubscription, JSON.stringify(payload)); } 
      catch (err) { if (err.statusCode === 410 || err.statusCode === 404) await pool.query("DELETE FROM push_subscriptions WHERE id = $1", [sub.id]); }
    }
  } catch (err) { console.error("Push xatosi:", err); }
}

async function isBlocked(username1, username2) {
  try {
    const result = await pool.query(
      `SELECT 1 FROM ${BLOCKED_USERS_TABLE} b
       JOIN ${USERS_TABLE} u1 ON b.blocker_id = u1.id
       JOIN ${USERS_TABLE} u2 ON b.blocked_id = u2.id
       WHERE (u1.username = $1 AND u2.username = $2) OR (u1.username = $2 AND u2.username = $1) LIMIT 1`,
      [username1, username2]
    );
    return result.rowCount > 0;
  } catch { return false; }
}

async function sendAllUsers(targetBrowser = null) {
  try {
    const { rows } = await pool.query(`SELECT id, username, avatar, full_name, last_seen FROM users`);
    const usersList = rows.map(u => ({
      id: u.id, username: u.username, avatar: u.avatar, full_name: u.full_name,
      online: hasLiveSockets(u.username) || isPresenceGraceActive(u.username),
      lastActive: lastActiveTime.get(u.username) || (u.last_seen ? new Date(u.last_seen).getTime() : null)
    }));
    if (targetBrowser) targetBrowser.emit("ONLINE_USERS_LIST", usersList);
    else browsers.forEach(b => b.emit("ONLINE_USERS_LIST", usersList));
  } catch (err) { console.error("User list error:", err); }
}

// --- ASOSIY HANDLER ---

function registerSocketHandlers(io) {
  io.on("connection", (browser) => {
    browsers.push(browser);

    browser.on("USER_ONLINE", (username) => {
      if (!username) return;
      browser.username = username;
      clearPendingOfflineTimeout(username);
      if (!onlineUsers.has(username)) onlineUsers.set(username, new Set());
      onlineUsers.get(username).add(browser);

      sendAllUsers();
      browser.broadcast.emit("USER_STATUS_CHANGED", { username, online: true });

      // Call Sync
      const activeCall = getUserActiveCall(username);
      if (activeCall) {
        if (activeCall.status !== "connected" && activeCall.callee === username && activeCall.latestOffer) {
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
      }

      const pending = consumePendingCallOffer(username);
      if (pending) emitToUser(username, "CALL_OFFER", pending.payload);
    });

    // --- VIDEO CALL (WebRTC) SIGNALING ---

    browser.on("CALL_OFFER", async (data) => {
      const { target, offer, isVideo, caller } = data;
      const callerUsername = browser.username;
      if (!callerUsername || !target) return;

      if (await isBlocked(callerUsername, target)) {
        return browser.emit("CALL_BLOCKED", { target });
      }

      const callId = data.callId || `call_${Date.now()}_${callerUsername}`;
      const session = upsertCallSession({ callId, caller: callerUsername, callee: target, isVideo, callerInfo: caller });
      session.latestOffer = offer;

      const delivered = emitToUser(target, "CALL_OFFER", { callId, caller, offer, isVideo, resume: false });
      
      if (!delivered) {
        const pendingOffer = {
          payload: { callId, caller, offer, isVideo, resume: false },
          timeout: setTimeout(() => {
            if (pendingCallOffers.has(target)) {
              pendingCallOffers.delete(target);
              finalizeCallSession(callId);
              emitToUser(callerUsername, "CALL_NOT_DELIVERED", { target });
              sendPushToUser(target, { title: callerUsername, body: isVideo ? "Video qo'ng'iroq" : "Audio qo'ng'iroq", tag: "call-"+callerUsername });
            }
          }, CALL_OFFER_DELIVERY_GRACE_MS)
        };
        pendingCallOffers.set(target, pendingOffer);
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

    browser.on("ICE_CANDIDATE", (data) => {
      const { target, candidate, callId } = data;
      if (target) emitToUser(target, "ICE_CANDIDATE", { candidate, callId });
    });

    browser.on("CALL_REJECT", async (data) => {
      const { target, callId } = data;
      emitToUser(target, "CALL_REJECT", { callId });
      finalizeCallSession(callId);
      await saveCallMessage(target, browser.username, data.isVideo, 0);
    });

    browser.on("CALL_END", async (data) => {
      const { target, callId, duration } = data;
      emitToUser(target, "CALL_END", { callId, reason: "hangup" });
      const session = finalizeCallSession(callId);
      const finalDuration = duration || (session?.connectedAt ? Math.round((Date.now() - session.connectedAt)/1000) : 0);
      await saveCallMessage(browser.username, target, data.isVideo, finalDuration);
    });

    // --- MESSAGE HANDLERS ---
    browser.on("NEW_MESSAGE", async (data) => {
       // ... (Xabar saqlash mantiqi o'zgarishsiz qoladi)
       // Ammo emitToUser funksiyasidan foydalaning
    });

    browser.on("disconnect", () => {
      const username = browser.username;
      const index = browsers.indexOf(browser);
      if (index > -1) browsers.splice(index, 1);

      if (username && onlineUsers.has(username)) {
        const sockets = onlineUsers.get(username);
        sockets.delete(browser);
        if (sockets.size === 0) {
          pendingOfflineTimeouts.set(username, setTimeout(() => {
            onlineUsers.delete(username);
            sendAllUsers();
            browser.broadcast.emit("USER_STATUS_CHANGED", { username, online: false });
          }, PRESENCE_OFFLINE_GRACE_MS));
        }
      }
    });
  });
}

// Qo'ng'iroq xabarini bazaga yozish funksiyasi
async function saveCallMessage(caller, target, isVideo, duration) {
  try {
    const callerRes = await pool.query(`SELECT id FROM users WHERE username = $1`, [caller]);
    const targetRes = await pool.query(`SELECT id FROM users WHERE username = $1`, [target]);
    if (callerRes.rowCount === 0 || targetRes.rowCount === 0) return;

    const callerId = callerRes.rows[0].id;
    const targetId = targetRes.rows[0].id;
    const [u1, u2] = callerId < targetId ? [callerId, targetId] : [targetId, callerId];

    let chat = await pool.query(`SELECT id FROM chats WHERE user1_id=$1 AND user2_id=$2`, [u1, u2]);
    let chatId = chat.rowCount > 0 ? chat.rows[0].id : (await pool.query(`INSERT INTO chats(user1_id, user2_id) VALUES($1,$2) RETURNING id`, [u1,u2])).rows[0].id;

    const type = isVideo ? "video" : "audio";
    const content = duration > 0 ? `__CALL:${type}:${duration}__` : `__CALL:${type}:missed__`;
    const msg = await pool.query(`INSERT INTO messages(chat_id, sender_id, content) VALUES($1,$2,$3) RETURNING id, created_at`, [chatId, callerId, content]);

    const payload = { id: msg.rows[0].id, user: caller, receiver: target, message: content, created_at: msg.rows[0].created_at };
    emitToUser(caller, "NEW_MESSAGE", payload);
    emitToUser(target, "NEW_MESSAGE", payload);
  } catch (e) { console.error("Call history error:", e); }
}

export { registerSocketHandlers };