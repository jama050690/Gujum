import { Router } from "express";
import { pool } from "../config/database.js";

const router = Router();

// Push subscription saqlash
router.post("/push/subscribe", async (req, res) => {
  try {
    const { subscription, username } = req.body;
    if (!subscription || !username) {
      return res.status(400).json({ message: "subscription va username kerak" });
    }

    const { endpoint, keys } = subscription;
    if (!endpoint || !keys?.p256dh || !keys?.auth) {
      return res.status(400).json({ message: "Noto'g'ri subscription format" });
    }

    // User ID olish
    const userResult = await pool.query("SELECT id FROM users WHERE username = $1", [username]);
    if (userResult.rowCount === 0) {
      return res.status(404).json({ message: "User topilmadi" });
    }
    const userId = userResult.rows[0].id;

    // Upsert — endpoint unique, yangilash yoki qo'shish
    await pool.query(
      `INSERT INTO push_subscriptions (user_id, endpoint, p256dh, auth)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (endpoint) DO UPDATE SET user_id = $1, p256dh = $3, auth = $4`,
      [userId, endpoint, keys.p256dh, keys.auth]
    );

    res.json({ message: "Subscribed" });
  } catch (err) {
    console.error("Push subscribe xato:", err);
    res.status(500).json({ message: "Server xatosi" });
  }
});

// Push subscription o'chirish
router.delete("/push/unsubscribe", async (req, res) => {
  try {
    const { endpoint } = req.body;
    if (!endpoint) {
      return res.status(400).json({ message: "endpoint kerak" });
    }
    await pool.query("DELETE FROM push_subscriptions WHERE endpoint = $1", [endpoint]);
    res.json({ message: "Unsubscribed" });
  } catch (err) {
    console.error("Push unsubscribe xato:", err);
    res.status(500).json({ message: "Server xatosi" });
  }
});

export default router;
