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

// 1. Http serverni yaratamiz
const httpServer = http.createServer(app);

// 2. Socket.io serverini Flutter va Web uchun optimallashtiramiz
const io = new Server(httpServer, {
  path: '/api/bootchat/socket.io/',
  cors: {
    origin: "*", // Xavfsizlik uchun keyinchalik domenlarni cheklashingiz mumkin
    methods: ["GET", "POST"],
    credentials: true
  },
  // --- FLUTTER TIMEOUT VA VIDEO CALL UCHUN MUHIM SOZLAMALAR ---
  transports: ['websocket', 'polling'], // Websocket birinchi navbatda
  pingTimeout: 60000,   // Flutter ulanishni yo'qotmasligi uchun 60s
  pingInterval: 25000,  // Har 25s da aloqani tekshirish
  connectTimeout: 45000, 
  maxHttpBufferSize: 1e7 // 10MB (Katta rasmlar yoki signaling xabarlari uchun)
});

// 3. Socket handlerlarni ulaymiz
registerSocketHandlers(io);

async function start() {
  ensureUploadsDir();
  
  try {
    await initDb();
    startCleanupScheduler();

    // 0.0.0.0 barcha tarmoq interfeyslaridan ulanishni qabul qiladi
    httpServer.listen(PORT, '0.0.0.0', () => {
      console.log(`=========================================`);
      console.log(`✅ Backend port: ${PORT} da ishga tushdi`);
      console.log(`🔗 Socket Path: /api/bootchat/socket.io/`);
      console.log(`🚀 Video Call Signaling tayyor`);
      console.log(`=========================================`);
    });
  } catch (error) {
    // Swallowing this left the process alive but never listening — a far harder
    // failure to spot than a crash. Die instead and let the supervisor surface it.
    console.error('❌ Ma\'lumotlar bazasi yoki Clean-upda xato:', error);
    process.exit(1);
  }
}

// Xatoliklarni ushlash (Server o'chib qolmasligi uchun)
process.on("unhandledRejection", (reason, promise) => {
  console.error("Unhandled Rejection at:", promise, "reason:", reason);
});

process.on("uncaughtException", (err) => {
  console.error("Uncaught Exception:", err);
  // EADDRINUSE — port band, 3 soniya kutib qayta urinish
  if (err.code === 'EADDRINUSE') {
    console.error(`Port ${PORT} band! 3 soniyadan keyin qayta uriniladi...`);
    setTimeout(() => start().catch(console.error), 3000);
  }
  // Boshqa xatolar uchun PM2 restart qilsin
});

start().catch((error) => {
  console.error('❌ Backendni ishga tushirishda xato:', error);
  process.exit(1);
});