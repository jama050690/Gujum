import { Router } from 'express';
import { pool } from '../config/database.js';

const router = Router();

// Jadval mavjud bo'lmasa yaratish.
//
// Kalit — token, username emas. Avval username PRIMARY KEY edi va har bir
// foydalanuvchida faqat bitta token saqlanardi: ikkinchi qurilmadan kirilsa
// yoki APK qayta o'rnatilsa eski qator ustiga yozilib, birinchi qurilma
// qo'ng'iroqlarni umuman olmay qolardi. Token esa har bir o'rnatma uchun
// yagona, shuning uchun tabiiy kalit ham o'sha.
pool.query(`
  CREATE TABLE IF NOT EXISTS fcm_tokens (
    token      TEXT PRIMARY KEY,
    username   TEXT NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW()
  )
`).catch(e => console.error('[FCM] table error:', e.message));

// Eski sxemadan (username PRIMARY KEY) ko'chirish. Yangi o'rnatmalarda
// pastdagilar hech narsa qilmaydi.
(async () => {
  try {
    await pool.query(`ALTER TABLE fcm_tokens DROP CONSTRAINT IF EXISTS fcm_tokens_pkey`);
    await pool.query(`ALTER TABLE fcm_tokens ALTER COLUMN username SET NOT NULL`);
    // Bir xil token ikki marta yozilgan bo'lsa — eskisini tashlaymiz.
    await pool.query(`
      DELETE FROM fcm_tokens a USING fcm_tokens b
      WHERE a.token = b.token AND a.updated_at < b.updated_at
    `);
    await pool.query(`
      DO $$ BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM pg_constraint WHERE conname = 'fcm_tokens_token_pkey'
        ) THEN
          ALTER TABLE fcm_tokens ADD CONSTRAINT fcm_tokens_token_pkey PRIMARY KEY (token);
        END IF;
      END $$;
    `);
    await pool.query(
      `CREATE INDEX IF NOT EXISTS fcm_tokens_username_idx ON fcm_tokens (username)`
    );
  } catch (e) {
    console.error('[FCM] token jadvalini ko\'chirishda xato:', e.message);
  }
})();

// FCM tokenni saqlash
router.post('/fcm-token', async (req, res) => {
  const { username, token } = req.body;
  if (!username || !token) {
    return res.status(400).json({ error: 'username va token kerak' });
  }
  try {
    // Token boshqa akkauntga tegishli bo'lsa (bitta qurilmada boshqa user
    // kirgan) — egasi yangilanadi, qator ko'paymaydi.
    await pool.query(
      `INSERT INTO fcm_tokens (token, username, updated_at) VALUES ($1, $2, NOW())
       ON CONFLICT (token) DO UPDATE SET username = EXCLUDED.username, updated_at = NOW()`,
      [token, username]
    );
    res.json({ ok: true });
  } catch (e) {
    console.error('[FCM] token save error:', e.message);
    res.status(500).json({ error: 'Server xatosi' });
  }
});

// FCM tokenni o'chirish (logout).
// Token berilsa faqat shu qurilma o'chadi — boshqa qurilmalar qo'ng'iroq
// olishda davom etadi. Token berilmasa (eski klientlar) hammasi o'chadi.
router.delete('/fcm-token', async (req, res) => {
  const { username, token } = req.body;
  try {
    if (token) {
      await pool.query('DELETE FROM fcm_tokens WHERE token = $1', [token]);
    } else if (username) {
      await pool.query('DELETE FROM fcm_tokens WHERE username = $1', [username]);
    }
  } catch (e) {
    console.error('[FCM] token delete error:', e.message);
  }
  res.json({ ok: true });
});

export default router;
