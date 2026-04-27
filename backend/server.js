import "./src/config/env.js";
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { Server } from 'socket.io';

import app from './src/app.js';
import { startCleanupScheduler } from './src/config/cleanup.js';
import { initDb } from './src/db/init.js';
import { registerSocketHandlers } from './src/socket/handler.js';

const PORT = Number(process.env.PORT || 3003);
const UPLOADS_DIR = path.resolve('uploads');

function ensureUploadsDir() {
  if (!fs.existsSync(UPLOADS_DIR)) {
    fs.mkdirSync(UPLOADS_DIR, { recursive: true });
    console.log(`Uploads papkasi yaratildi: ${UPLOADS_DIR}`);
  }
}

// Http serverni yaratamiz
const httpServer = http.createServer(app);

// SOCKET.IO SOZLAMASI (Nginx bilan mos kelishi uchun)
socket.on("ICE_CANDIDATE", (data) => {
  // data: { target: 'urinov', candidate: {...}, callId: '...' }
  const targetSocket = users[data.target]; // Target socketni topish
  if (targetSocket) {
    io.to(targetSocket).emit("ICE_CANDIDATE", {
      candidate: data.candidate,
      callId: data.callId
    });
  }
});

// Socket handlerlarni ulaymiz
registerSocketHandlers(io);

async function start() {
  ensureUploadsDir();
  await initDb();
  startCleanupScheduler();

  httpServer.listen(PORT, '0.0.0.0', () => {
    console.log(`✅ Backend http://0.0.0.0:${PORT} portida ishga tushdi`);
    console.log(`✅ Socket Path: /api/bootchat/socket.io/`);
  });
}

start().catch((error) => {
  console.error('❌ Backendni ishga tushirishda xato:', error);
  process.exit(1);
});