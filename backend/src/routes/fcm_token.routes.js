import { Router } from 'express';
import { pool } from '../config/database.js';

const router = Router();

// Jadval mavjud bo'lmasa yaratish
pool.query(`
  CREATE TABLE IF NOT EXISTS fcm_tokens (
    username   TEXT PRIMARY KEY,
    token      TEXT NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW()
  )
`).catch(e => console.error('[FCM] table error:', e.message));

// FCM tokenni saqlash
router.post('/fcm-token', async (req, res) => {
  const { username, token } = req.body;
  if (!username || !token) {
    return res.status(400).json({ error: 'username va token kerak' });
  }
  try {
    await pool.query(
      `INSERT INTO fcm_tokens (username, token, updated_at) VALUES ($1, $2, NOW())
       ON CONFLICT (username) DO UPDATE SET token = EXCLUDED.token, updated_at = NOW()`,
      [username, token]
    );
    res.json({ ok: true });
  } catch (e) {
    console.error('[FCM] token save error:', e.message);
    res.status(500).json({ error: 'Server xatosi' });
  }
});

// FCM tokenni o'chirish (logout)
router.delete('/fcm-token', async (req, res) => {
  const { username } = req.body;
  if (username) {
    await pool
      .query('DELETE FROM fcm_tokens WHERE username = $1', [username])
      .catch(() => {});
  }
  res.json({ ok: true });
});

export default router;
