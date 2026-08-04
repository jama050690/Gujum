import express from "express";
import nodemailer from "nodemailer";
import argon2 from "argon2";
import "../config/env.js";
import { pool, USERS_TABLE } from "../config/database.js";
import { upload } from "../config/upload.js";

const router = express.Router();

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// In-memory OTP storage: email -> { code, expiresAt, userData }
const otpStore = new Map();

const SMTP_HOST = process.env.SMTP_HOST;
const SMTP_PORT = Number(process.env.SMTP_PORT || 587);
const SMTP_SECURE = String(process.env.SMTP_SECURE || "false").toLowerCase() === "true";
const SMTP_USER = process.env.SMTP_USER;
const SMTP_PASS = process.env.SMTP_PASS;
const SMTP_FROM = process.env.SMTP_FROM || SMTP_USER;
const ALLOW_DEV_OTP_FALLBACK =
  String(process.env.ALLOW_DEV_OTP_FALLBACK || "false").toLowerCase() === "true";
let transporterVerified = false;

const transporter = nodemailer.createTransport({
  host: SMTP_HOST,
  port: SMTP_PORT,
  secure: SMTP_SECURE,
  auth: {
    user: SMTP_USER,
    pass: SMTP_PASS,
  },
});

function generateOTP() {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

async function ensureEmailTransport() {
  if (transporterVerified) return true;

  await transporter.verify();
  transporterVerified = true;
  return true;
}

async function sendOtpEmail({ to, subject, html }) {
  const hasEmailConfig = Boolean(SMTP_HOST && SMTP_PORT && SMTP_USER && SMTP_PASS && SMTP_FROM);
  if (!hasEmailConfig) {
    console.error(`❌ Email yuborilmadi: SMTP sozlamalari to'liq emas | SMTP_HOST=${SMTP_HOST || "❌"} SMTP_USER=${SMTP_USER || "❌"} SMTP_PASS=${SMTP_PASS ? "✅" : "❌"} SMTP_FROM=${SMTP_FROM || "❌"}`);
    return { sent: false, reason: "missing_email_config" };
  }

  try {
    await ensureEmailTransport();
    const info = await transporter.sendMail({
      from: `"Bootchat" <${SMTP_FROM}>`,
      to,
      subject,
      html,
    });
    // messageId is generated locally from SMTP_FROM, so it proves nothing about
    // delivery. info.accepted/rejected and the SMTP response are what matter.
    if (!info.accepted?.length) {
      console.error(
        `❌ Email qabul qilinmadi: ${to} | rejected: ${JSON.stringify(info.rejected)} | ${info.response}`,
      );
      return { sent: false, reason: "not_accepted" };
    }

    console.log(`✅ Email yuborildi: ${to} | ${info.response}`);
    return { sent: true };
  } catch (err) {
    console.error(`❌ Email yuborilmadi: ${to} | Xato: ${err?.message}`);
    return { sent: false, reason: err?.message || "send_failed" };
  }
}

function buildOtpResponse({ mailResult, successMessage, fallbackMessage, extra = {} }) {
  if (mailResult.sent) {
    return {
      status: 200,
      body: {
        message: successMessage,
        ...extra,
      },
    };
  }

  if (ALLOW_DEV_OTP_FALLBACK) {
    return {
      status: 200,
      body: {
        message: fallbackMessage,
        emailStatus: mailResult.reason,
        ...extra,
      },
    };
  }

  return {
    status: 503,
    body: {
      message: "Email yuborish sozlanmagan yoki vaqtincha ishlamayapti",
      emailStatus: mailResult.reason,
    },
  };
}

router.post("/send-otp", upload.single("profilePic"), async (req, res) => {
  const { fullName, username, phone, email, password, age, gender } = req.body;
  const normalizedFullName = String(fullName || "").trim();
  const normalizedUsername = String(username || "").trim();
  const normalizedPhone = String(phone || "").trim();
  const normalizedEmail = String(email || "").trim();
  const normalizedAge = Number(age);
  const normalizedGender = gender === true || gender === "true";

  if (!normalizedFullName || !normalizedUsername || !normalizedPhone || !normalizedEmail || !password || !normalizedAge || gender === undefined) {
    return res.status(400).json({ message: "Barcha maydonlarni to'ldiring" });
  }

  if (!EMAIL_REGEX.test(normalizedEmail)) {
    return res.status(400).json({ message: "Email formati noto'g'ri" });
  }

  try {
    const existing = await pool.query(
      `SELECT id FROM ${USERS_TABLE} WHERE LOWER(username) = LOWER($1) OR LOWER(email) = LOWER($2)`,
      [normalizedUsername, normalizedEmail]
    );

    if (existing.rowCount > 0) {
      return res.status(400).json({ message: "Bu username yoki email allaqachon ro'yxatdan o'tgan" });
    }

    const code = generateOTP();
    const expiresAt = Date.now() + 5 * 60 * 1000;

    otpStore.set(normalizedEmail.toLowerCase(), {
      code,
      expiresAt,
      userData: {
        fullName: normalizedFullName,
        username: normalizedUsername,
        phone: normalizedPhone,
        email: normalizedEmail,
        password,
        age: normalizedAge,
        gender: normalizedGender,
        avatar: req.file ? `/uploads/${req.file.filename}` : null,
      },
    });

    const mailResult = await sendOtpEmail({
      to: normalizedEmail,
      subject: "Bootchat - Tasdiqlash kodi",
      html: `
        <div style="font-family: Arial, sans-serif; max-width: 420px; margin: 0 auto; padding: 24px; text-align: center;">
          <h2 style="color: #3b82f6;">Bootchat</h2>
          <p style="color: #666;">Salom, <strong>${normalizedFullName}</strong>!</p>
          <p style="color: #666;">Sizning tasdiqlash kodingiz:</p>
          <div style="background: linear-gradient(135deg, #3b82f6, #8b5cf6); color: white; font-size: 32px; font-weight: bold; letter-spacing: 8px; padding: 20px; border-radius: 12px; margin: 20px 0;">
            ${code}
          </div>
          <p style="color: #999; font-size: 13px;">Kod 5 daqiqa ichida amal qiladi.</p>
        </div>
      `,
    });

    const response = buildOtpResponse({
      mailResult,
      successMessage: "Tasdiqlash kodi yuborildi",
      fallbackMessage: "Email sozlanmagani uchun OTP server javobida qaytarildi (dev)",
      extra: {
        email: normalizedEmail,
        ...(mailResult.sent ? {} : { devOtp: code }),
      },
    });
    return res.status(response.status).json(response.body);
  } catch (err) {
    console.error("OTP yuborishda xato:", err?.message || err);
    return res.status(500).json({
      message: "OTP yuborishda server xatolik berdi",
      details: err?.message || "unknown_error",
    });
  }
});

router.post("/verify-otp", async (req, res) => {
  const email = String(req.body.email || "").trim().toLowerCase();
  const code = String(req.body.code || "").trim();

  if (!email || !code) {
    return res.status(400).json({ message: "Email va kodni kiriting" });
  }

  const otpData = otpStore.get(email);
  if (!otpData) {
    return res.status(400).json({ message: "OTP topilmadi. Qaytadan so'rang" });
  }

  if (Date.now() > otpData.expiresAt) {
    otpStore.delete(email);
    return res.status(400).json({ message: "Kod muddati tugagan. Qaytadan so'rang" });
  }

  if (otpData.code !== code) {
    return res.status(400).json({ message: "Noto'g'ri kod" });
  }

  try {
    const {
      fullName,
      username,
      phone,
      email: rawEmail,
      password,
      age,
      gender,
      avatar,
    } = otpData.userData;
    const existing = await pool.query(
      `SELECT id FROM ${USERS_TABLE} WHERE LOWER(username) = LOWER($1) OR LOWER(email) = LOWER($2)`,
      [username, rawEmail]
    );
    if (existing.rowCount > 0) {
      otpStore.delete(email);
      return res.status(400).json({ message: "Bu username yoki email allaqachon ro'yxatdan o'tgan" });
    }

    const passwordHash = await argon2.hash(password);
    await pool.query(
      `INSERT INTO ${USERS_TABLE} (full_name, username, phone, email, password_hash, age, gender, avatar) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [
        fullName,
        username,
        phone,
        rawEmail,
        passwordHash,
        Number(age),
        gender === true || gender === "true",
        avatar || null,
      ]
    );

    otpStore.delete(email);
    return res.json({ message: "Ro'yxatdan o'tish muvaffaqiyatli yakunlandi", verified: true });
  } catch (err) {
    console.error("OTP verifyda user yaratishda xato:", err);
    return res.status(500).json({ message: "Ro'yxatdan o'tishda xatolik yuz berdi" });
  }
});

router.post("/resend-otp", async (req, res) => {
  const email = String(req.body.email || "").trim().toLowerCase();
  if (!email) {
    return res.status(400).json({ message: "Email kiriting" });
  }

  const otpData = otpStore.get(email);
  if (!otpData) {
    return res.status(400).json({ message: "Avval ro'yxatdan o'ting" });
  }

  const code = generateOTP();
  otpData.code = code;
  otpData.expiresAt = Date.now() + 5 * 60 * 1000;

  try {
    const mailResult = await sendOtpEmail({
      to: otpData.userData.email,
      subject: "Bootchat - Yangi tasdiqlash kodi",
      html: `
        <div style="font-family: Arial, sans-serif; max-width: 420px; margin: 0 auto; padding: 24px; text-align: center;">
          <h2 style="color: #3b82f6;">Bootchat</h2>
          <p style="color: #666;">Yangi tasdiqlash kodingiz:</p>
          <div style="background: linear-gradient(135deg, #3b82f6, #8b5cf6); color: white; font-size: 32px; font-weight: bold; letter-spacing: 8px; padding: 20px; border-radius: 12px; margin: 20px 0;">
            ${code}
          </div>
          <p style="color: #999; font-size: 13px;">Kod 5 daqiqa ichida amal qiladi.</p>
        </div>
      `,
    });

    const response = buildOtpResponse({
      mailResult,
      successMessage: "Yangi kod yuborildi",
      fallbackMessage: "Email sozlanmagani uchun OTP server javobida qaytarildi (dev)",
      extra: {
        ...(mailResult.sent ? {} : { devOtp: code }),
      },
    });
    return res.status(response.status).json(response.body);
  } catch (err) {
    console.error("OTP qayta yuborishda xato:", err?.message || err);
    return res.status(500).json({
      message: "OTP qayta yuborishda server xatolik berdi",
      details: err?.message || "unknown_error",
    });
  }
});

// ==================== FORGOT PASSWORD ====================

const resetOtpStore = new Map();

router.post("/forgot-password", async (req, res) => {
  const email = String(req.body.email || "").trim();

  if (!email || !EMAIL_REGEX.test(email)) {
    return res.status(400).json({ message: "To'g'ri email kiriting" });
  }

  try {
    const result = await pool.query(
      `SELECT id, full_name FROM ${USERS_TABLE} WHERE LOWER(email) = LOWER($1)`,
      [email]
    );

    if (result.rowCount === 0) {
      return res.status(400).json({ message: "Bu email bilan hisob topilmadi" });
    }

    const user = result.rows[0];
    const code = generateOTP();
    const expiresAt = Date.now() + 5 * 60 * 1000;

    resetOtpStore.set(email.toLowerCase(), {
      code,
      expiresAt,
      userId: user.id,
    });

    const mailResult = await sendOtpEmail({
      to: email,
      subject: "Bootchat - Parolni tiklash",
      html: `
        <div style="font-family: Arial, sans-serif; max-width: 420px; margin: 0 auto; padding: 24px; text-align: center;">
          <h2 style="color: #3b82f6;">Bootchat</h2>
          <p style="color: #666;">Salom, <strong>${user.full_name}</strong>!</p>
          <p style="color: #666;">Parolni tiklash uchun kod:</p>
          <div style="background: linear-gradient(135deg, #ef4444, #f97316); color: white; font-size: 32px; font-weight: bold; letter-spacing: 8px; padding: 20px; border-radius: 12px; margin: 20px 0;">
            ${code}
          </div>
          <p style="color: #999; font-size: 13px;">Kod 5 daqiqa ichida amal qiladi.</p>
        </div>
      `,
    });

    const response = buildOtpResponse({
      mailResult,
      successMessage: "Parolni tiklash kodi yuborildi",
      fallbackMessage: "Email sozlanmagani uchun OTP server javobida qaytarildi (dev)",
      extra: {
        email,
        ...(mailResult.sent ? {} : { devOtp: code }),
      },
    });
    return res.status(response.status).json(response.body);
  } catch (err) {
    console.error("Forgot password xato:", err?.message || err);
    return res.status(500).json({ message: "Server xatolik berdi" });
  }
});

router.post("/reset-password", async (req, res) => {
  const email = String(req.body.email || "").trim().toLowerCase();
  const code = String(req.body.code || "").trim();
  const newPassword = req.body.newPassword;

  if (!email || !code || !newPassword) {
    return res.status(400).json({ message: "Email, kod va yangi parolni kiriting" });
  }

  const otpData = resetOtpStore.get(email);
  if (!otpData) {
    return res.status(400).json({ message: "OTP topilmadi. Qaytadan so'rang" });
  }

  if (Date.now() > otpData.expiresAt) {
    resetOtpStore.delete(email);
    return res.status(400).json({ message: "Kod muddati tugagan. Qaytadan so'rang" });
  }

  if (otpData.code !== code) {
    return res.status(400).json({ message: "Noto'g'ri kod" });
  }

  try {
    const passwordHash = await argon2.hash(newPassword);
    await pool.query(
      `UPDATE ${USERS_TABLE} SET password_hash = $1 WHERE id = $2`,
      [passwordHash, otpData.userId]
    );

    resetOtpStore.delete(email);
    return res.json({ message: "Parol muvaffaqiyatli yangilandi" });
  } catch (err) {
    console.error("Reset password xato:", err?.message || err);
    return res.status(500).json({ message: "Parolni yangilashda xatolik" });
  }
});

export default router;
