import { createContext, useContext, useEffect, useState } from "react";
import { io } from "socket.io-client";
import { registerServiceWorker, subscribeToPush } from "@/utils/notifications";
import { getBaseUrl } from "@/utils/api";

const SOCKET_PATH =
  import.meta.env.VITE_SOCKET_PATH || "/api/socket.io";
const SocketContext = createContext(null);

function isLocalHostname(hostname = "") {
  return hostname === "localhost" || hostname === "127.0.0.1";
}

function getSocketTransportOptions() {
  if (typeof window === "undefined") {
    return {
      transports: ["websocket", "polling"],
      upgrade: true,
    };
  }

  if (isLocalHostname(window.location.hostname)) {
    return {
      transports: ["websocket", "polling"],
      upgrade: true,
    };
  }

  // Production reverse proxy is not upgrading websocket connections reliably.
  // Force polling so the client stays connected without console websocket errors.
  return {
    transports: ["polling"],
    upgrade: false,
  };
}

function getSocketOrigin(baseUrl) {
  if (!baseUrl) return undefined;
  if (!baseUrl.startsWith("http")) return undefined;

  try {
    return new URL(baseUrl).origin;
  } catch {
    return undefined;
  }
}

export function SocketProvider({ children, username }) {
  const [socket, setSocket] = useState(null);
  const [connected, setConnected] = useState(false);

  useEffect(() => {
    if (!username) return;

    const baseUrl = getBaseUrl();
    const socketOrigin = getSocketOrigin(baseUrl);
    const transportOptions = getSocketTransportOptions();
    const s = io(socketOrigin, {
      path: SOCKET_PATH,
      withCredentials: true,
      transports: transportOptions.transports,
      upgrade: transportOptions.upgrade,
      reconnection: true,
      reconnectionAttempts: Infinity,
      reconnectionDelay: 1000,
      reconnectionDelayMax: 5000,
    });
    setSocket(s);

    s.on("connect", () => {
      setConnected(true);
      s.emit("USER_ONLINE", username);
    });

    // Service Worker va Push Notification ro'yxatdan o'tkazish
    registerServiceWorker().then(() => {
      subscribeToPush(username);
    });

    s.on("disconnect", () => setConnected(false));

    return () => {
      s.off("connect");
      s.off("disconnect");
      s.disconnect();
      setSocket(null);
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
