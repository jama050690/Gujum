import express from "express";
import { pool, USERS_TABLE, FRIENDS_TABLE } from "../config/database.js";
import { authMiddleware } from "../middleware/auth.js";

const router = express.Router();

// POST /api/friends/request — Do'stlik so'rovi yuborish
router.post("/request", authMiddleware, async (req, res) => {
  const { targetUsername } = req.body;
  const senderId = req.user.id;

  if (!targetUsername) {
    return res.status(400).json({ message: "targetUsername kerak" });
  }

  try {
    const target = await pool.query(
      `SELECT id FROM ${USERS_TABLE} WHERE username = $1`,
      [targetUsername]
    );
    if (target.rowCount === 0) {
      return res.status(404).json({ message: "User topilmadi" });
    }

    const receiverId = target.rows[0].id;
    if (receiverId === senderId) {
      return res.status(400).json({ message: "O'zingizga so'rov yuborib bo'lmaydi" });
    }

    // Allaqachon do'stlik bormi tekshirish (ikkala tomonga)
    const existing = await pool.query(
      `SELECT id, status FROM ${FRIENDS_TABLE}
       WHERE (sender_id = $1 AND receiver_id = $2)
          OR (sender_id = $2 AND receiver_id = $1)`,
      [senderId, receiverId]
    );

    if (existing.rowCount > 0) {
      const row = existing.rows[0];
      if (row.status === "accepted") {
        return res.status(400).json({ message: "Allaqachon do'stsiz" });
      }
      if (row.status === "pending") {
        return res.status(400).json({ message: "So'rov allaqachon yuborilgan" });
      }
    }

    await pool.query(
      `INSERT INTO ${FRIENDS_TABLE} (sender_id, receiver_id, status) VALUES ($1, $2, 'pending')`,
      [senderId, receiverId]
    );

    res.json({ sent: true, targetUsername });
  } catch (err) {
    console.error("Do'stlik so'rovi yuborishda xato:", err);
    res.status(500).json({ message: "Xatolik yuz berdi" });
  }
});

// GET /api/friends/requests — Menga kelgan pending so'rovlar
router.get("/requests", authMiddleware, async (req, res) => {
  const userId = req.user.id;

  try {
    const { rows } = await pool.query(
      `SELECT f.id, u.username, u.avatar, f.created_at
       FROM ${FRIENDS_TABLE} f
       JOIN ${USERS_TABLE} u ON f.sender_id = u.id
       WHERE f.receiver_id = $1 AND f.status = 'pending'
       ORDER BY f.created_at DESC`,
      [userId]
    );

    res.json(rows);
  } catch (err) {
    console.error("So'rovlarni olishda xato:", err);
    res.status(500).json({ message: "Xatolik yuz berdi" });
  }
});

// GET /api/friends/sent — Men yuborgan pending so'rovlar
router.get("/sent", authMiddleware, async (req, res) => {
  const userId = req.user.id;

  try {
    const { rows } = await pool.query(
      `SELECT f.id, u.username, u.avatar, f.created_at
       FROM ${FRIENDS_TABLE} f
       JOIN ${USERS_TABLE} u ON f.receiver_id = u.id
       WHERE f.sender_id = $1 AND f.status = 'pending'
       ORDER BY f.created_at DESC`,
      [userId]
    );

    res.json(rows);
  } catch (err) {
    console.error("Yuborilgan so'rovlarni olishda xato:", err);
    res.status(500).json({ message: "Xatolik yuz berdi" });
  }
});

// POST /api/friends/accept — So'rovni qabul qilish
router.post("/accept", authMiddleware, async (req, res) => {
  const { requestId } = req.body;
  const userId = req.user.id;

  if (!requestId) {
    return res.status(400).json({ message: "requestId kerak" });
  }

  try {
    const result = await pool.query(
      `UPDATE ${FRIENDS_TABLE} SET status = 'accepted'
       WHERE id = $1 AND receiver_id = $2 AND status = 'pending'
       RETURNING sender_id`,
      [requestId, userId]
    );

    if (result.rowCount === 0) {
      return res.status(404).json({ message: "So'rov topilmadi" });
    }

    res.json({ accepted: true });
  } catch (err) {
    console.error("So'rovni qabul qilishda xato:", err);
    res.status(500).json({ message: "Xatolik yuz berdi" });
  }
});

// POST /api/friends/reject — So'rovni rad etish
router.post("/reject", authMiddleware, async (req, res) => {
  const { requestId } = req.body;
  const userId = req.user.id;

  if (!requestId) {
    return res.status(400).json({ message: "requestId kerak" });
  }

  try {
    await pool.query(
      `DELETE FROM ${FRIENDS_TABLE} WHERE id = $1 AND receiver_id = $2 AND status = 'pending'`,
      [requestId, userId]
    );

    res.json({ rejected: true });
  } catch (err) {
    console.error("So'rovni rad etishda xato:", err);
    res.status(500).json({ message: "Xatolik yuz berdi" });
  }
});

// GET /api/friends — Mening do'stlarim (accepted)
router.get("/", authMiddleware, async (req, res) => {
  const userId = req.user.id;

  try {
    const { rows } = await pool.query(
      `SELECT u.id, u.username, u.avatar, u.full_name
       FROM ${FRIENDS_TABLE} f
       JOIN ${USERS_TABLE} u ON (
         CASE WHEN f.sender_id = $1 THEN f.receiver_id ELSE f.sender_id END
       ) = u.id
       WHERE (f.sender_id = $1 OR f.receiver_id = $1)
         AND f.status = 'accepted'
       ORDER BY u.username ASC`,
      [userId]
    );

    res.json(rows);
  } catch (err) {
    console.error("Do'stlarni olishda xato:", err);
    res.status(500).json({ message: "Xatolik yuz berdi" });
  }
});

// DELETE /api/friends/:username — Do'stlikdan chiqarish
router.delete("/:username", authMiddleware, async (req, res) => {
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

    await pool.query(
      `DELETE FROM ${FRIENDS_TABLE}
       WHERE ((sender_id = $1 AND receiver_id = $2) OR (sender_id = $2 AND receiver_id = $1))`,
      [userId, targetId]
    );

    res.json({ removed: true, username });
  } catch (err) {
    console.error("Do'stlikdan chiqarishda xato:", err);
    res.status(500).json({ message: "Xatolik yuz berdi" });
  }
});

// GET /api/friends/status/:username — Biror user bilan do'stlik holati
router.get("/status/:username", authMiddleware, async (req, res) => {
  const userId = req.user.id;
  const { username } = req.params;

  try {
    const target = await pool.query(
      `SELECT id FROM ${USERS_TABLE} WHERE username = $1`,
      [username]
    );
    if (target.rowCount === 0) {
      return res.json({ status: "none" });
    }

    const targetId = target.rows[0].id;

    const result = await pool.query(
      `SELECT status, sender_id FROM ${FRIENDS_TABLE}
       WHERE (sender_id = $1 AND receiver_id = $2)
          OR (sender_id = $2 AND receiver_id = $1)`,
      [userId, targetId]
    );

    if (result.rowCount === 0) {
      return res.json({ status: "none" });
    }

    const row = result.rows[0];
    if (row.status === "accepted") {
      return res.json({ status: "friends" });
    }
    if (row.sender_id === userId) {
      return res.json({ status: "sent" });
    }
    return res.json({ status: "received", requestId: result.rows[0].id });
  } catch (err) {
    console.error("Status tekshirishda xato:", err);
    res.status(500).json({ message: "Xatolik yuz berdi" });
  }
});

export default router;
