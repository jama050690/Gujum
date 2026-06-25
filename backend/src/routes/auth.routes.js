import express from "express";
import argon2 from "argon2";
import jwt from "jsonwebtoken";
import "../config/env.js";
import { pool, USERS_TABLE } from "../config/database.js";
import { upload } from "../config/upload.js";
import { imageContentCheck } from "../config/content_filter.js";

const router = express.Router();

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const GOOGLE_ISSUERS = new Set(["https://accounts.google.com", "accounts.google.com"]);
const USERNAME_MAX_LEN = 25;
const EMAIL_MAX_LEN = 35;

function createHttpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

function makeSafeUsername(raw) {
  const cleaned = String(raw || "")
    .toLowerCase()
    .replace(/[^a-z0-9_]/g, "");
  return cleaned.slice(0, USERNAME_MAX_LEN);
}

async function getAvailableUsername(seed) {
  const base = makeSafeUsername(seed) || "user";

  for (let i = 0; i < 1000; i += 1) {
    const suffix = i === 0 ? "" : String(i);
    const rootMax = Math.max(1, USERNAME_MAX_LEN - suffix.length);
    const candidate = `${base.slice(0, rootMax)}${suffix}`;

    const exists = await pool.query(
      `SELECT id FROM ${USERS_TABLE} WHERE LOWER(username) = LOWER($1) LIMIT 1`,
      [candidate]
    );
    if (exists.rowCount === 0) return candidate;
  }

  const fallback = `user${Date.now().toString().slice(-8)}`.slice(0, USERNAME_MAX_LEN);
  return fallback;
}

function setSessionCookie(res, user) {
  const token = jwt.sign(
    {
      id: user.id,
      username: user.username,
      is_premium: user.is_premium,
      role: user.role || "user",
    },
    process.env.JWT_SECRET,
    { expiresIn: "7d" }
  );

  res.cookie("access_token", token, {
    httpOnly: true,
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
    path: "/",
    maxAge: 7 * 24 * 60 * 60 * 1000, // 7 kun
  });
}

function formatUser(user, avatarOverride = user.avatar) {
  return {
    username: user.username,
    fullName: user.full_name,
    phone: user.phone,
    birthday: user.birthday,
    bio: user.bio,
    avatar: avatarOverride,
    role: user.role || "user",
  };
}

async function verifyGoogleCredential(credential, expectedAud) {
  if (!credential) {
    throw createHttpError(400, "Google credential yuborilmadi");
  }
  if (!expectedAud) {
    throw createHttpError(500, "Google login backend sozlanmagan");
  }

  let payload;
  try {
    const response = await fetch(
      `https://oauth2.googleapis.com/tokeninfo?id_token=${encodeURIComponent(credential)}`
    );
    payload = await response.json();
    if (!response.ok || payload.error_description || payload.error) {
      throw new Error(payload.error_description || payload.error || "Token noto'g'ri");
    }
  } catch {
    throw createHttpError(401, "Google token tasdiqlanmadi");
  }

  if (!GOOGLE_ISSUERS.has(payload.iss)) {
    throw createHttpError(401, "Google issuer noto'g'ri");
  }

  if (payload.aud !== expectedAud) {
    throw createHttpError(401, "Google client id mos emas");
  }

  if (payload.exp && Number(payload.exp) * 1000 < Date.now()) {
    throw createHttpError(401, "Google token muddati tugagan");
  }

  if (String(payload.email_verified) !== "true") {
    throw createHttpError(401, "Google email tasdiqlanmagan");
  }

  return payload;
}

// POST /api/signup
router.post("/signup", async (req, res) => {
  console.log(
    `${new Date().toISOString()} da ${req.url}ga ${req.method} API chaqiruv keldi.`,
  );

  const { fullName, username, email, password, age, gender } = req.body;
  const normalizedUsername = String(username || "").trim();
  const normalizedFullName = String(fullName || "").trim();
  const normalizedEmail = String(email || "").trim();

  if (!normalizedFullName || !normalizedUsername || !password || !normalizedEmail || !age || gender === undefined || gender === null)
    return res.status(400).json({ message: "Missing fields" });

  if (!EMAIL_REGEX.test(normalizedEmail)) {
    return res.status(400).json({ message: "Email formati noto'g'ri" });
  }

  const hashed = await argon2.hash(password);
  try {
    const result = await pool.query(
      `INSERT INTO ${USERS_TABLE} (full_name, username, email, password_hash, age, gender, role)
       VALUES ($1, $2, $3, $4, $5, $6, 'user')
       RETURNING id, username, role`,
      [normalizedFullName, normalizedUsername, normalizedEmail, hashed, age, gender],
    );
    res.json({
      message: "User registered",
      user: {
        username: result.rows[0].username,
        role: result.rows[0].role,
      },
    });
  } catch (err) {
    console.error(err.message || err);
    res.status(400).json({
      message: `User ro'yhatdan o'tishda xatolik yuz berdi: ${err.message || err}`,
    });
  }
});

// POST /api/login
router.post("/login", upload.single("profilePic"), imageContentCheck, async (req, res) => {
  console.log(
    `${new Date().toISOString()} da ${req.url}ga ${req.method} API chaqiruv keldi.`,
  );
  const { username, password } = req.body;
  const normalizedUsername = String(username || "").trim();
  if (!normalizedUsername || !password) {
    return res.status(400).json({ message: "Username va parol kerak" });
  }
  const result = await pool.query(
    `SELECT * FROM ${USERS_TABLE} WHERE LOWER(username)=LOWER($1)`,
    [normalizedUsername],
  );

  if (result.rowCount === 0) {
    console.log(result.rowCount);
    return res.status(401).json({ message: "Invalid credentials" });
  }
  console.log(result.rowCount);

  const user = result.rows[0];
  let match = false;
  try {
    match = await argon2.verify(user.password_hash, password);
  } catch (err) {
    console.error("Password verify xato:", err.message);
    return res.status(401).json({ message: "Invalid credentials" });
  }
  console.log(match);
  if (!match) return res.status(401).json({ message: "Invalid credentials" });

  // Agar yangi avatar yuklangan bo'lsa, uni saqlash
  let avatarPath = user.avatar;
  if (req.file) {
    avatarPath = `/uploads/${req.file.filename}`;
    await pool.query(`UPDATE ${USERS_TABLE} SET avatar=$1 WHERE id=$2`, [
      avatarPath,
      user.id,
    ]);
  }

  setSessionCookie(res, user);
  res.json({
    message: "Login success",
    user: formatUser(user, avatarPath),
  });
});

// POST /api/login/google
router.post("/login/google", async (req, res) => {
  console.log(
    `${new Date().toISOString()} da ${req.url}ga ${req.method} API chaqiruv keldi.`,
  );

  try {
    const credential = String(req.body?.credential || "").trim();
    const googleClientId = process.env.GOOGLE_CLIENT_ID || process.env.VITE_GOOGLE_CLIENT_ID;
    const googleAndroidClientId = process.env.GOOGLE_ANDROID_CLIENT_ID;

    let googlePayload;
    try {
      googlePayload = await verifyGoogleCredential(credential, googleClientId);
    } catch (err) {
      if (googleAndroidClientId) {
        googlePayload = await verifyGoogleCredential(credential, googleAndroidClientId);
      } else {
        throw err;
      }
    }

    const normalizedEmail = String(googlePayload.email || "").trim().toLowerCase();
    if (!normalizedEmail || !EMAIL_REGEX.test(normalizedEmail)) {
      throw createHttpError(400, "Google email formati noto'g'ri");
    }
    if (normalizedEmail.length > EMAIL_MAX_LEN) {
      throw createHttpError(400, "Google email juda uzun");
    }

    const normalizedFullName = String(googlePayload.name || "Google User")
      .trim()
      .slice(0, 50);
    const googleAvatar = String(googlePayload.picture || "").trim() || null;

    let userResult = await pool.query(
      `SELECT * FROM ${USERS_TABLE} WHERE LOWER(email)=LOWER($1) LIMIT 1`,
      [normalizedEmail]
    );

    let user = userResult.rows[0];

    if (!user) {
      const emailPrefix = normalizedEmail.split("@")[0];
      const username = await getAvailableUsername(emailPrefix || normalizedFullName || "user");
      const passwordHash = await argon2.hash(
        `google:${googlePayload.sub || normalizedEmail}:${Date.now()}`
      );

      const insertResult = await pool.query(
        `INSERT INTO ${USERS_TABLE} (username, email, password_hash, age, gender, full_name, avatar)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         RETURNING *`,
        [
          username,
          normalizedEmail,
          passwordHash,
          18,
          true,
          normalizedFullName || username,
          googleAvatar,
        ]
      );
      user = insertResult.rows[0];
    } else {
      const newFullName = user.full_name || normalizedFullName || user.username;
      const newAvatar = googleAvatar && (!user.avatar || user.avatar.startsWith("http"))
        ? googleAvatar
        : user.avatar;

      if (newFullName !== user.full_name || newAvatar !== user.avatar) {
        const updateResult = await pool.query(
          `UPDATE ${USERS_TABLE}
           SET full_name = $1, avatar = $2
           WHERE id = $3
           RETURNING *`,
          [newFullName, newAvatar, user.id]
        );
        user = updateResult.rows[0];
      }
    }

    setSessionCookie(res, user);
    res.json({
      message: "Login success",
      user: formatUser(user),
    });
  } catch (err) {
    console.error("Google login xato:", err.message || err);
    const status = err.status || 500;
    res.status(status).json({
      message: err.message || "Google login xatoligi",
    });
  }
});

// GET /api/me
router.get("/me", (req, res) => {
  console.log(
    `${new Date().toISOString()} da ${req.url}ga ${req.method} API chaqiruv keldi.`,
  );
  const token = req.cookies.access_token;
  if (!token) return res.sendStatus(401);

  try {
    const user = jwt.verify(token, process.env.JWT_SECRET);
    res.json({ user });
  } catch {
    res.sendStatus(403);
  }
});

// POST /api/logout
router.post("/logout", (_req, res) => {
  res.clearCookie("access_token", {
    httpOnly: true,
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
    path: "/",
  });
  res.json({ message: "Logout success" });
});

export default router;
