import { createContext, useContext, useEffect, useState, useRef } from "react";
import { io } from "socket.io-client";
import { registerServiceWorker, subscribeToPush } from "@/utils/notifications";
import { getBaseUrl } from "@/utils/api";

const DEFAULT_SOCKET_PATHS = [
  "/socket.io",
  "/api/socket.io",
  "/api/bootchat/socket.io",
];

const SocketContext = createContext(null);

function normalizeSocketPath(path = "") {
  const trimmed = String(path || "").trim();
  if (!trimmed) return "";
  if (/^https?:\/\//i.test(trimmed)) {
    try {
      return new URL(trimmed).pathname.replace(/\/+$/, "") || "/";
    } catch { return ""; }
  }
  const normalized = trimmed.startsWith("/") ? trimmed : `/${trimmed}`;
  return normalized.replace(/\/+$/, "") || "/";
}

function getSocketPaths() {
  const configuredPath = normalizeSocketPath(import.meta.env.VITE_SOCKET_PATH || "");
  return [
    ...new Set(
      [configuredPath, ...DEFAULT_SOCKET_PATHS.map(normalizeSocketPath)].filter(Boolean)
    ),
  ];
}

export function SocketProvider({ children, username }) {
  const [socket, setSocket] = useState(null);
  const [connected, setConnected] = useState(false);
  const socketRef = useRef(null);

  useEffect(() => {
    if (!username) return;

    const baseUrl = getBaseUrl();
    const socketOrigin = baseUrl ? new URL(baseUrl).origin : window.location.origin;
    const socketPaths = getSocketPaths();
    
    let isDisposed = false;

    const cleanup = (s) => {
      if (!s) return;
      s.removeAllListeners();
      s.disconnect();
    };

    const connect = (index) => {
      if (isDisposed || index >= socketPaths.length) return;

      const path = socketPaths[index];
      if (socketRef.current) cleanup(socketRef.current);

      const newSocket = io(socketOrigin, {
        path: path,
        withCredentials: true,
        transports: ["websocket", "polling"],
        reconnection: true,
        reconnectionAttempts: 10, // Ko'paytirildi
        reconnectionDelay: 2000,
        timeout: 20000,
      });

      socketRef.current = newSocket;

      newSocket.on("connect", () => {
        if (isDisposed) return;
        console.log("✅ Socket ulandi:", newSocket.id);
        setConnected(true);
        setSocket(newSocket);
        newSocket.emit("USER_ONLINE", username);
      });

      newSocket.on("connect_error", (err) => {
        if (isDisposed) return;
        console.warn(`⚠️ Socket ulanish xatosi (Path: ${path}):`, err.message);
        
        if (!newSocket.connected && index < socketPaths.length - 1) {
          cleanup(newSocket);
          connect(index + 1);
        }
      });

      // --- WEBRTC SIGNALING LISTENERLARINI SHU YERGA QO'SHAMIZ ---
      // Bu logikalar Calling ulanishi uchun shart!
      
      newSocket.on("CALL_OFFER", (data) => {
          console.log("📞 Kiruvchi qo'ng'iroq:", data.from);
          // Bu yerda Event yoki State orqali CallScreen-ni ochish kerak
      });

      newSocket.on("ICE_CANDIDATE", (data) => {
          // Tarmoq yo'llarini almashish
          window.dispatchEvent(new CustomEvent("webRTC_ice_candidate", { detail: data }));
      });

      newSocket.on("disconnect", (reason) => {
        console.log("❌ Socket uzildi:", reason);
        setConnected(false);
        if (reason === "io server disconnect" || reason === "transport close") {
          newSocket.connect();
        }
      });
    };

    connect(0);

    registerServiceWorker().then(() => {
      subscribeToPush(username).catch(err => console.error("Push xatosi:", err));
    });

    return () => {
      isDisposed = true;
      cleanup(socketRef.current);
      setSocket(null);
      setConnected(false);
    };
  }, [username]);

  return (
    <SocketContext.Provider value={{ socket, connected }}>
      {children}
    </SocketContext.Provider>
  );
}

export function useSocket() {
  const ctx = useContext(SocketContext);
  if (!ctx) throw new Error("useSocket must be used within SocketProvider");
  return ctx;
}