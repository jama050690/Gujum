import { createContext, useContext, useEffect, useState, useRef } from "react";
import { io } from "socket.io-client";
import { registerServiceWorker, subscribeToPush } from "@/utils/notifications";
import { getBaseUrl } from "@/utils/api";

const SocketContext = createContext(null);

export function SocketProvider({ children, username }) {
  const [socket, setSocket] = useState(null);
  const [connected, setConnected] = useState(false);
  const socketRef = useRef(null);

  useEffect(() => {
    if (!username) return;

    const baseUrl = getBaseUrl();
    const socketOrigin = baseUrl
      ? new URL(baseUrl).origin
      : window.location.origin;

    // Faqat bitta, to'g'ri path — fallback yo'q
    const socketPath =
      import.meta.env.VITE_SOCKET_PATH || "/api/bootchat/socket.io/";

    let isDisposed = false;

    const cleanup = (s) => {
      if (!s) return;
      s.removeAllListeners();
      s.disconnect();
    };

    if (socketRef.current) cleanup(socketRef.current);

    const newSocket = io(socketOrigin, {
      path: socketPath,
      withCredentials: true,
      transports: ["websocket", "polling"],
      reconnection: true,
      reconnectionAttempts: 10,
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
      console.warn(`⚠️ Socket ulanish xatosi (${socketPath}):`, err.message);
    });

    newSocket.on("ICE_CANDIDATE", (data) => {
      window.dispatchEvent(
        new CustomEvent("webRTC_ice_candidate", { detail: data })
      );
    });

    newSocket.on("disconnect", (reason) => {
      if (isDisposed) return;
      console.log("❌ Socket uzildi:", reason);
      setConnected(false);
    });

    registerServiceWorker().then(() => {
      subscribeToPush(username).catch((err) =>
        console.error("Push xatosi:", err)
      );
    });

    return () => {
      isDisposed = true;
      cleanup(socketRef.current);
      socketRef.current = null;
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