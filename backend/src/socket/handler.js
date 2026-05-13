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

// Qo'ng'iroq xabarini saqlash mantiqi (Sizning mavjud bazangizga mos)
async function saveCallMessage(caller, target, isVideo, duration) {
  try {
    const type = isVideo ? "video" : "audio";
    const content = duration > 0 ? `__CALL:${type}:${duration}__` : `__CALL:${type}:missed__`;
    // DB INSERT mantiqi bu yerda...
  } catch (e) { console.error("Call log error", e); }
}

async function sendAllUsers() {
    // Sizning sendAllUsers funksiyangiz...
}

export { registerSocketHandlers };