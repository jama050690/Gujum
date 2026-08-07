import express from "express";
import fs from "fs";
import path from "path";
import {
  pool,
  USERS_TABLE,
  CHATS_TABLE,
  MESSAGES_TABLE,
} from "../config/database.js";
import { authMiddleware } from "../middleware/auth.js";

const router = express.Router();
const UPLOADS_DIR = "uploads";

// O'chirilgan akkauntlarning arxivi: audit uchun 2 yil saqlanadi, keyin
// retention ishi tozalaydi. Bu yerda faqat kim va nima uchun ketgani turadi —
// yozishmalar, media va ijtimoiy graf o'chirish paytida butunlay yo'q qilinadi.
pool
  .query(
    `CREATE TABLE IF NOT EXISTS deleted_accounts (
       id SERIAL PRIMARY KEY,
       user_id INT,
       username TEXT,
       email TEXT,
       full_name TEXT,
       phone TEXT,
       role TEXT,
       registered_at TIMESTAMPTZ,
       reason TEXT,
       comment TEXT,
       deleted_at TIMESTAMPTZ DEFAULT NOW()
     )`
  )
  .catch((e) => console.error("[ACCOUNT] deleted_accounts jadvali:", e.message));

/**
 * Faqat shu foydalanuvchiga tegishli fayllarni o'chiradi.
 * Yo'l uploads/ ichidan chiqmasligini tekshiramiz — DB dagi qiymat
 * buzilgan bo'lsa ham boshqa papkaga tegib ketmasin.
 */
function removeUpload(storedPath) {
  if (!storedPath) return;
  const name = path.basename(String(storedPath));
  if (!name || name === "." || name === "..") return;
  const target = path.resolve(UPLOADS_DIR, name);
  if (!target.startsWith(path.resolve(UPLOADS_DIR))) return;
  try {
    if (fs.existsSync(target)) fs.unlinkSync(target);
  } catch (e) {
    console.error("[ACCOUNT] fayl o'chirilmadi:", e.message);
  }
}

// DELETE /api/account — akkauntni butunlay o'chirish
//
// Google Play akkaunt yaratadigan ilovalardan ilova ichida o'chirish
// imkonini talab qiladi, shuning uchun bu ixtiyoriy emas.
router.delete("/account", authMiddleware, async (req, res) => {
  const userId = req.user.id;
  const reason = req.body?.reason ? String(req.body.reason).slice(0, 100) : null;
  const comment = req.body?.comment ? String(req.body.comment).slice(0, 500) : null;
  const client = await pool.connect();

  try {
    await client.query("BEGIN");

    // O'chiriladigan fayllarni oldindan yig'amiz: qatorlar ketgandan keyin
    // yo'llarni bilib bo'lmaydi. Fayllar faqat commit muvaffaqiyatli
    // bo'lgandan keyin o'chiriladi.
    const files = [];
    const avatar = await client.query(
      `SELECT avatar FROM ${USERS_TABLE} WHERE id = $1`,
      [userId]
    );
    if (avatar.rows[0]?.avatar) files.push(avatar.rows[0].avatar);

    const media = await client.query(
      `SELECT image AS f FROM ${MESSAGES_TABLE} WHERE sender_id = $1 AND image IS NOT NULL
       UNION ALL SELECT audio FROM ${MESSAGES_TABLE} WHERE sender_id = $1 AND audio IS NOT NULL
       UNION ALL SELECT video FROM ${MESSAGES_TABLE} WHERE sender_id = $1 AND video IS NOT NULL`,
      [userId]
    );
    for (const row of media.rows) if (row.f) files.push(row.f);

    // 1. Yozishmalar. Xabarlar boshqa odamning chatida ham qolmaydi —
    // Telegram ham shunday qiladi.
    const chats = await client.query(
      `SELECT id FROM ${CHATS_TABLE} WHERE user1_id = $1 OR user2_id = $1`,
      [userId]
    );
    const chatIds = chats.rows.map((r) => r.id);
    if (chatIds.length > 0) {
      await client.query(
        `DELETE FROM ${MESSAGES_TABLE} WHERE chat_id = ANY($1::int[])`,
        [chatIds]
      );
      await client.query(`DELETE FROM ${CHATS_TABLE} WHERE id = ANY($1::int[])`, [
        chatIds,
      ]);
    }

    // 2. Ijtimoiy graf va qurilma yozuvlari. blocked_users, spam_reports,
    // friends va push_subscriptions da ON DELETE CASCADE bor, lekin
    // fcm_tokens username bo'yicha saqlanadi — uni qo'lda o'chiramiz.
    const username = req.user.username
      ? req.user.username
      : (
          await client.query(`SELECT username FROM ${USERS_TABLE} WHERE id = $1`, [
            userId,
          ])
        ).rows[0]?.username;
    if (username) {
      await client.query(`DELETE FROM fcm_tokens WHERE username = $1`, [username]);
    }

    // 6. Audit nusxasi: akkaunt ma'lumotlari va ketish sababi arxivga
    // ko'chiriladi. Foydalanuvchi uchun akkaunt yo'q, lekin 2 yil davomida
    // kim qachon va nima uchun ketganini ko'rsatib bera olamiz.
    await client.query(
      `INSERT INTO deleted_accounts
         (user_id, username, email, full_name, phone, role, reason, comment)
       SELECT id, username, email, full_name, phone, role, $2, $3
       FROM ${USERS_TABLE} WHERE id = $1`,
      [userId, reason, comment]
    );

    // 7. Akkauntning o'zi.
    await client.query(`DELETE FROM ${USERS_TABLE} WHERE id = $1`, [userId]);

    await client.query("COMMIT");

    // Fayllar tranzaksiyadan tashqarida: ularni qaytarib bo'lmaydi, shuning
    // uchun faqat baza o'zgarishi tasdiqlangandan keyin tegamiz.
    for (const file of files) removeUpload(file);

    res.clearCookie("access_token", { path: "/" });
    console.log(`[ACCOUNT] ${username || userId} akkaunti o'chirildi`);
    return res.json({ deleted: true });
  } catch (err) {
    await client.query("ROLLBACK").catch(() => {});
    console.error("[ACCOUNT] o'chirishda xato:", err.message);
    return res.status(500).json({ message: "Akkauntni o'chirib bo'lmadi" });
  } finally {
    client.release();
  }
});

export default router;
