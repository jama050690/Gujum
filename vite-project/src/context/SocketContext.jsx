import { createContext, useContext, useEffect, useState } from "react";
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
    } catch {
      return "";
    }
  }

  const normalized = trimmed.startsWith("/") ? trimmed : `/${trimmed}`;
  return normalized.replace(/\/+$/, "") || "/";
}

function getSocketPaths() {
  const configuredPath = normalizeSocketPath(import.meta.env.VITE_SOCKET_PATH || "");

  return [
    ...new Set(
      [configuredPath, ...DEFAULT_SOCKET_PATHS.map(normalizeSocketPath)].filter(Boolean),
    ),
  ];
}

function isLocalHostname(hostname = "") {
  return hostname === "localhost" || hostname === "127.0.0.1";
}

function getSocketTransportOptions(baseUrl) {
  const origin = getSocketOrigin(baseUrl);
  const hostname = origin ? new URL(origin).hostname : window.location.hostname;
  const preferWebSocketOnly = !isLocalHostname(hostname);

  return {
    transports: preferWebSocketOnly ? ["websocket"] : ["websocket", "polling"],
    upgrade: !preferWebSocketOnly,
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
    const transportOptions = getSocketTransportOptions(baseUrl);
    const socketPaths = getSocketPaths();
    let activeSocket = null;
    let disposed = false;

    const cleanupSocket = (target) => {
      if (!target) return;
      target.off("connect");
      target.off("connect_error");
      target.off("disconnect");
      target.disconnect();
    };

    const connectWithPath = (pathIndex = 0) => {
      if (disposed || pathIndex >= socketPaths.length) {
        setConnected(false);
        setSocket(null);
        return;
      }

      const currentPath = socketPaths[pathIndex];
      let connectedOnce = false;

      const nextSocket = io(socketOrigin, {
        path: currentPath,
        withCredentials: true,
        transports: transportOptions.transports,
        upgrade: transportOptions.upgrade,
        rememberUpgrade: transportOptions.transports.length === 1,
        reconnection: true,
        reconnectionAttempts: Infinity,
        reconnectionDelay: 1500,
        reconnectionDelayMax: 8000,
        timeout: 15000,
      });

      activeSocket = nextSocket;
      setSocket(nextSocket);

      nextSocket.on("connect", () => {
        connectedOnce = true;
        setConnected(true);
        nextSocket.emit("USER_ONLINE", username);
      });

      nextSocket.on("connect_error", () => {
        if (disposed || connectedOnce || activeSocket !== nextSocket) return;
        cleanupSocket(nextSocket);
        connectWithPath(pathIndex + 1);
      });

      nextSocket.on("disconnect", () => {
        setConnected(false);
      });
    };

    connectWithPath();

    // Service Worker va Push Notification ro'yxatdan o'tkazish
    registerServiceWorker().then(() => {
      subscribeToPush(username);
    });

    return () => {
      disposed = true;
      cleanupSocket(activeSocket);
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
