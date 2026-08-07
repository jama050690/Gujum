import express from "express";
import cors from "cors";
import cookieParser from "cookie-parser";
import path from "path";
import { fileURLToPath } from "url";

// Route importlari
import authRoutes from "./routes/auth.routes.js";
import otpRoutes from "./routes/otp.routes.js";
import userRoutes from "./routes/user.routes.js";
import messageRoutes from "./routes/message.routes.js";
import groupRoutes from "./routes/group.routes.js";
import channelRoutes from "./routes/channel.routes.js";
import uploadRoutes from "./routes/upload.routes.js";
import blockRoutes from "./routes/block.routes.js";
import spamRoutes from "./routes/spam.routes.js";
import friendRoutes from "./routes/friend.routes.js";
import pushRoutes from "./routes/push.routes.js";
import adminRoutes from "./routes/admin.routes.js";
import fcmTokenRoutes from "./routes/fcm_token.routes.js";
import accountRoutes from "./routes/account.routes.js";

const app = express();
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// 1. CORS sozlamalari (Socket.io ulanishi uchun juda muhim)
// Flutter va Web versiyalaringiz turli domenlarda bo'lsa, origin qismini aniq ko'rsatish tavsiya etiladi
app.use(
  cors({
    origin: ["https://jamshiddin.uz", "http://localhost:3000", "http://localhost:5173"], 
    credentials: true,
  }),
);

// 2. Standart Middleware'lar
// Har bir so'rov: usul, yo'l, status va davomiyligi. Ilgari faqat ba'zi
// yo'llar log yozardi, shuning uchun "serverda hech qanday log yo'q" degani
// so'rov kelmadimi yoki jimgina bajarildimi — ajratib bo'lmasdi.
app.use((req, res, next) => {
  const started = Date.now();
  res.on("finish", () => {
    const ms = Date.now() - started;
    // Sekin so'rovlar ko'zga tashlanib tursin.
    const mark = ms >= 1000 ? " ⏱ SEKIN" : "";
    console.log(`${req.method} ${req.originalUrl} → ${res.statusCode} ${ms}ms${mark}`);
  });
  next();
});

app.use(cookieParser());
app.use(express.json({ limit: "50mb" })); // Katta hajmli JSON (masalan, base64 rasmlar) uchun limitni oshirish
app.use(express.urlencoded({ extended: true, limit: "50mb" }));

// 3. Statik fayllar (Rasm va videolar uchun)
// nosniff stops the browser second-guessing the content type on user-uploaded
// files and executing one as HTML in our origin.
app.use(
  "/uploads",
  express.static(path.join(__dirname, "../uploads"), {
    setHeaders: (res) => {
      res.setHeader("X-Content-Type-Options", "nosniff");
      res.setHeader("Content-Security-Policy", "default-src 'none'");
    },
  })
);
app.use("/static", express.static(path.join(__dirname, "public")));

// 4. API Routes
app.use("/api", authRoutes);
app.use("/api", otpRoutes);
app.use("/api", messageRoutes);
app.use("/api", uploadRoutes);
app.use("/api/users", userRoutes);
app.use("/api/groups", groupRoutes);
app.use("/api/channels", channelRoutes);
app.use("/api/block", blockRoutes);
app.use("/api/spam", spamRoutes);
app.use("/api/friends", friendRoutes);
app.use("/api", pushRoutes);
app.use("/api", fcmTokenRoutes);
app.use("/api", accountRoutes);
app.use("/api/admin", adminRoutes);

// 5. Salomatlik tekshiruvi (Health Check)
app.get("/health", (req, res) => {
  res.status(200).json({ status: "ok", message: "Server is running" });
});

// 6. Xatoliklarni ushlash (Error Handling Middleware)
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({
    success: false,
    message: "Ichki server xatosi yuz berdi",
    error: process.env.NODE_ENV === "development" ? err.message : {}
  });
});

export default app;