import "./src/config/env.js";
import http from 'node:http';

import { Server } from 'socket.io';

import app from './src/app.js';
import { startCleanupScheduler } from './src/config/cleanup.js';
import { initDb } from './src/db/init.js';
import { registerSocketHandlers } from './src/socket/handler.js';

const PORT = Number(process.env.PORT || 4000);

function resolveSocketPaths() {
  const fallbackPaths = ['/socket.io', '/api/socket.io', '/api/bootchat/socket.io'];
  const configured = process.env.SOCKET_PATHS || process.env.SOCKET_PATH;
  if (!configured) {
    return fallbackPaths;
  }

  return [...new Set([
    ...configured
      .split(',')
      .map((item) => item.trim())
      .filter(Boolean),
    ...fallbackPaths,
  ])];
}

const SOCKET_PATHS = resolveSocketPaths();

const httpServer = http.createServer(app);
for (const socketPath of SOCKET_PATHS) {
  const io = new Server(httpServer, {
    cors: {
      origin: true,
      credentials: true,
    },
    path: socketPath,
  });

  registerSocketHandlers(io);
}

async function start() {
  await initDb();
  startCleanupScheduler();

  httpServer.listen(PORT, '0.0.0.0', () => {
    console.log(
      `Bootchat backend listening on http://0.0.0.0:${PORT} with socket paths: ${SOCKET_PATHS.join(', ')}`,
    );
  });
}

start().catch((error) => {
  console.error('Backend failed to start:', error);
  process.exitCode = 1;
});
