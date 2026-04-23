import express from "express";
import cors from "cors";
import cookieParser from "cookie-parser";
import path from "path";
import { fileURLToPath } from "url";

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

const app = express();
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Global middleware
app.use(
  cors({
    origin: true,
    credentials: true,
  }),
);
app.use(cookieParser());
app.use(express.json());
app.use("/uploads", express.static("uploads"));
app.use("/static", express.static(path.join(__dirname, "public")));

// Routes
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
app.use("/api/admin", adminRoutes);

export default app;
