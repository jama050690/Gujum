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

// Pathlarni tozalash funksiyasi (o'zgarishsiz qoldi)
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
  
  // Socketni refda saqlash ulanishlarni boshqarish uchun qulayroq
  const socketRef = useRef(null);

  useEffect(() => {
    if (!username) return;

    const baseUrl = getBaseUrl();
    const socketOrigin = baseUrl ? new URL(baseUrl).origin : window.location.origin;
    const socketPaths = getSocketPaths();
    
    let isDisposed = false;
    let currentPathIndex = 0;

    const cleanup = (s) => {
      if (!s) return;
      s.removeAllListeners(); // Barcha listenerlarni o'chirish
      s.disconnect();
    };

    const connect = (index) => {
      if (isDisposed || index >= socketPaths.length) return;

      const path = socketPaths[index];
      
      // Agar avvalgi socket bo'lsa, tozalaymiz
      if (socketRef.current) cleanup(socketRef.current);

      const newSocket = io(socketOrigin, {
        path: path,
        withCredentials: true,
        transports: ["websocket", "polling"], // Avval websocket, bo'lmasa polling
        reconnection: true,
        reconnectionAttempts: 5, // Har bir path uchun limit qo'yamiz
        timeout: 10000,
      });

      socketRef.current = newSocket;

      newSocket.on("connect", () => {
        if (isDisposed) return;
        setConnected(true);
        setSocket(newSocket);
        newSocket.emit("USER_ONLINE", username);
      });

      newSocket.on("connect_error", (err) => {
        if (isDisposed) return;
        console.warn(`Socket ulanishda xato (Path: ${path}):`, err.message);
        
        // Agar birinchi path xato bersa, keyingisiga o'tamiz
        if (!newSocket.connected && index < socketPaths.length - 1) {
          cleanup(newSocket);
          connect(index + 1);
        }
      });

      newSocket.on("disconnect", (reason) => {
        setConnected(false);
        // Agar server o'zi uzib yuborsa (io server disconnect), qayta ulanishga urinadi
        if (reason === "io server disconnect") {
          newSocket.connect();
        }
      });
    };

    connect(currentPathIndex);

    // Notifications
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