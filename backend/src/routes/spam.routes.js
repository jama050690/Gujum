import express from "express";
import { pool, USERS_TABLE, BLOCKED_USERS_TABLE, SPAM_REPORTS_TABLE } from "../config/database.js";
import { authMiddleware } from "../middleware/auth.js";

const router = express.Router();

// POST /api/spam/report — Spam report + avtomatik bloklash
router.post("/report", authMiddleware, async (req, res) => {
  const { targetUsername, reason } = req.body;
  const reporterId = req.user.id;

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

    const reportedId = target.rows[0].id;
    if (reportedId === reporterId) {
      return res.status(400).json({ message: "O'zingizni report qilish mumkin emas" });
    }

    // Spam report saqlash
    await pool.query(
      `INSERT INTO ${SPAM_REPORTS_TABLE} (reporter_id, reported_id, reason) VALUES ($1, $2, $3)`,
      [reporterId, reportedId, reason || null]
    );

    // Avtomatik bloklash
    await pool.query(
      `INSERT INTO ${BLOCKED_USERS_TABLE} (blocker_id, blocked_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
      [reporterId, reportedId]
    );

    res.json({ reported: true, blocked: true, username: targetUsername });
  } catch (err) {
    console.error("Spam reportda xato:", err);
    res.status(500).json({ message: "Xatolik yuz berdi" });
  }
});

export default router;
