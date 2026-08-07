import express from "express";
import {
  pool,
  USERS_TABLE,
  CHATS_TABLE,
  MESSAGES_TABLE,
} from "../config/database.js";
import { authMiddleware } from "../middleware/auth.js";
import { emitToUser } from "../socket/handler.js";
import { upload } from "../config/upload.js";

const router = express.Router();

// GET /api/users
router.get("/", async (req, res) => {
  try {
    const { rows } = await pool.query(
      `SELECT username, avatar FROM ${USERS_TABLE}`
    );
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: "Userlarni olishda xatolik" });
  }
});

// GET /api/users/search
router.get("/search", async (req, res) => {
  const { q } = req.query;

  try {
    const query = `
      SELECT id, username, avatar, full_name FROM ${USERS_TABLE}
      ${q ? `WHERE (username ILIKE $1 OR full_name ILIKE $1)` : ''}
      ORDER BY username ASC
      LIMIT 50
    `;
    const params = q ? [`%${q}%`] : [];

    const { rows } = await pool.query(query, params);
    res.json(rows);
  } catch (err) {
    console.error("Userlarni qidirishda xato:", err);
    res.status(500).json({ message: "Xatolik yuz berdi" });
  }
});

// POST /api/users/phone-contacts — Telefon kontaktlaridan ro'yxatdagilarni topish
router.post("/phone-contacts", authMiddleware, async (req, res) => {
  const userId = req.user.id;
  const { phones } = req.body;

  if (!Array.isArray(phones) || phones.length === 0) {
    return res.status(400).json({ message: "phones massivi kerak" });
  }

  const normalize = (p) => String(p ?? "").replace(/\D/g, "").slice(-9);
  // Avval bu yerda .slice(0, 500) bor edi — katta manzillar kitobida 500 dan
  // keyingi raqamlar jimgina tashlab yuborilardi va kontakt "topilmadi" bo'lib
  // ko'rinardi. Endi hammasi tekshiriladi, faqat takrorlanuvchilar olib
  // tashlanadi (bir kontaktda bir nechta raqam bo'lishi odatiy hol).
  const normalized = [
    ...new Set(phones.map(normalize).filter((p) => p.length >= 7)),
  ];

  if (normalized.length === 0) return res.json([]);

  try {
    const { rows } = await pool.query(
      `SELECT id, username, avatar, full_name,
              RIGHT(REGEXP_REPLACE(phone, '\\D', '', 'g'), 9) AS matched_phone
       FROM ${USERS_TABLE}
       WHERE id != $1
         AND phone IS NOT NULL
         AND RIGHT(REGEXP_REPLACE(phone, '\\D', '', 'g'), 9) = ANY($2::text[])`,
      [userId, normalized]
    );
    res.json(rows);
  } catch (err) {
    console.error("Phone contacts matching xato:", err);
    res.status(500).json({ message: "Xatolik yuz berdi" });
  }
});

// GET /api/users/profile/:username — Foydalanuvchi profilini olish
router.get("/profile/:username", async (req, res) => {
  const { username } = req.params;
  try {
    const { rows } = await pool.query(
      `SELECT username, full_name, phone, bio, avatar, birthday FROM ${USERS_TABLE} WHERE username = $1`,
      [username]
    );
    if (rows.length === 0) {
      return res.status(404).json({ message: "User topilmadi" });
    }
    res.json(rows[0]);
  } catch (err) {
    console.error("Profilni olishda xato:", err);
    res.status(500).json({ message: "Xatolik yuz berdi" });
  }
});

// PUT /api/users/profile — Profil ma'lumotlarini yangilash
router.put("/profile", authMiddleware, upload.single("avatar"), async (req, res) => {
  const userId = req.user.id;
  const { phone, birthday, bio, full_name, phone_from_sim } = req.body;

  try {
    // Bitta raqam — bitta akkaunt. Aks holda ikki foydalanuvchi bir xil
    // raqamga ega bo'lib, kontaktlarda ikkalasi ham chiqib qolardi.
    if (phone !== undefined && phone !== null && String(phone).trim() !== "") {
      const taken = await pool.query(
        `SELECT id FROM ${USERS_TABLE}
         WHERE id != $1 AND phone IS NOT NULL
           AND RIGHT(REGEXP_REPLACE(phone, '\\D', '', 'g'), 9)
             = RIGHT(REGEXP_REPLACE($2, '\\D', '', 'g'), 9)
         LIMIT 1`,
        [userId, String(phone)]
      );
      if (taken.rowCount > 0) {
        return res
          .status(409)
          .json({ message: "Bu telefon raqami boshqa akkauntga biriktirilgan" });
      }
    }

    const fields = [];
    const values = [];
    let idx = 1;

    if (req.file) {
      const avatarPath = `/uploads/${req.file.filename}`;
      fields.push(`avatar = $${idx++}`);
      values.push(avatarPath);
    }
    if (full_name !== undefined) { fields.push(`full_name = $${idx++}`); values.push(full_name); }
    if (phone !== undefined) {
      fields.push(`phone = $${idx++}`);
      values.push(phone);
      // Audit maydonlari faqat raqam bilan birga yoziladi — ular o'sha
      // yozuvning qachon va qanday kelganini bildiradi.
      fields.push(`phone_set_at = NOW()`);
      // multipart orqali kelgani uchun qiymat satr bo'lishi mumkin.
      const fromSim =
        phone_from_sim === undefined || phone_from_sim === null || phone_from_sim === ''
          ? null
          : phone_from_sim === true || phone_from_sim === 'true';
      fields.push(`phone_from_sim = $${idx++}`);
      values.push(fromSim);
    }
    if (birthday !== undefined) { fields.push(`birthday = $${idx++}`); values.push(birthday || null); }
    if (bio !== undefined) { fields.push(`bio = $${idx++}`); values.push(bio); }

    if (fields.length === 0) {
      return res.status(400).json({ message: "Yangilanadigan maydon yo'q" });
    }

    values.push(userId);
    const result = await pool.query(
      `UPDATE ${USERS_TABLE} SET ${fields.join(", ")} WHERE id = $${idx} RETURNING avatar`,
      values
    );

    res.json({ updated: true, avatar: result.rows[0]?.avatar });
  } catch (err) {
    console.error("Profilni yangilashda xato:", err);
    res.status(500).json({ message: "Xatolik yuz berdi" });
  }
});

// DELETE /api/users/chat/:username — Chat tarixini o'chirish
router.delete("/chat/:username/history", authMiddleware, async (req, res) => {
  const userId = req.user.id;
  const { username } = req.params;

  try {
    const target = await pool.query(
      `SELECT id FROM ${USERS_TABLE} WHERE username = $1`,
      [username]
    );
    if (target.rowCount === 0) {
      return res.status(404).json({ message: "User topilmadi" });
    }

    const targetId = target.rows[0].id;
    const [user1Id, user2Id] =
      userId < targetId ? [userId, targetId] : [targetId, userId];

    const chat = await pool.query(
      `SELECT id FROM ${CHATS_TABLE} WHERE user1_id = $1 AND user2_id = $2`,
      [user1Id, user2Id]
    );

    if (chat.rowCount === 0) {
      return res.json({ cleared: true, username, deletedMessages: 0 });
    }

    const chatId = chat.rows[0].id;
    // Telegram singari tanlov: standart holatda faqat o'zimizdan o'chadi,
    // forEveryone=true bo'lsa ikkalasidan ham.
    const forEveryone = req.body?.forEveryone === true;

    let deletedMessages;
    if (forEveryone) {
      deletedMessages = await pool.query(
        `DELETE FROM ${MESSAGES_TABLE} WHERE chat_id = $1`,
        [chatId]
      );
      emitToUser(username, "CHAT_CLEARED", { by: req.user.username });
    } else {
      // Xabarlar bazada qoladi — suhbatdosh ularni ko'raveradi.
      deletedMessages = await pool.query(
        `INSERT INTO message_deletions (message_id, user_id)
         SELECT m.id, $2 FROM ${MESSAGES_TABLE} m
         WHERE m.chat_id = $1
         ON CONFLICT DO NOTHING`,
        [chatId, userId]
      );
    }

    res.json({
      cleared: true,
      username,
      forEveryone,
      deletedMessages: deletedMessages.rowCount,
    });
  } catch (err) {
    console.error("Chat tarixini tozalashda xato:", err);
    res.status(500).json({ message: "Xatolik yuz berdi" });
  }
});

router.delete("/chat/:username", authMiddleware, async (req, res) => {
  const userId = req.user.id;
  const { username } = req.params;

  try {
    const target = await pool.query(
      `SELECT id FROM ${USERS_TABLE} WHERE username = $1`,
      [username]
    );
    if (target.rowCount === 0) {
      return res.status(404).json({ message: "User topilmadi" });
    }

    const targetId = target.rows[0].id;
    const [user1Id, user2Id] = userId < targetId ? [userId, targetId] : [targetId, userId];

    // Chat va xabarlarni o'chirish
    const chat = await pool.query(
      `SELECT id FROM ${CHATS_TABLE} WHERE user1_id = $1 AND user2_id = $2`,
      [user1Id, user2Id]
    );

    if (chat.rowCount > 0) {
      const chatId = chat.rows[0].id;
      await pool.query(`DELETE FROM ${MESSAGES_TABLE} WHERE chat_id = $1`, [chatId]);
      await pool.query(`DELETE FROM ${CHATS_TABLE} WHERE id = $1`, [chatId]);
    }

    res.json({ deleted: true, username });
  } catch (err) {
    console.error("Chatni o'chirishda xato:", err);
    res.status(500).json({ message: "Xatolik yuz berdi" });
  }
});

export default router;
