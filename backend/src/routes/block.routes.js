import express from "express";
import { pool, USERS_TABLE, BLOCKED_USERS_TABLE } from "../config/database.js";
import { authMiddleware } from "../middleware/auth.js";

const router = express.Router();

// POST /api/block — Userni bloklash
router.post("/", authMiddleware, async (req, res) => {
  const { targetUsername } = req.body;
  const blockerId = req.user.id;

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

    const blockedId = target.rows[0].id;
    if (blockedId === blockerId) {
      return res.status(400).json({ message: "O'zingizni bloklash mumkin emas" });
    }

    await pool.query(
      `INSERT INTO ${BLOCKED_USERS_TABLE} (blocker_id, blocked_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
      [blockerId, blockedId]
    );

    res.json({ blocked: true, username: targetUsername });
  } catch (err) {
    console.error("Bloklashda xato:", err);
    res.status(500).json({ message: "Xatolik yuz berdi" });
  }
});

// DELETE /api/block/:username — Blokdan chiqarish
router.delete("/:username", authMiddleware, async (req, res) => {
  const blockerId = req.user.id;
  const { username } = req.params;

  try {
    const target = await pool.query(
      `SELECT id FROM ${USERS_TABLE} WHERE username = $1`,
      [username]
    );
    if (target.rowCount === 0) {
      return res.status(404).json({ message: "User topilmadi" });
    }

    await pool.query(
      `DELETE FROM ${BLOCKED_USERS_TABLE} WHERE blocker_id = $1 AND blocked_id = $2`,
      [blockerId, target.rows[0].id]
    );

    res.json({ unblocked: true, username });
  } catch (err) {
    console.error("Blokdan chiqarishda xato:", err);
    res.status(500).json({ message: "Xatolik yuz berdi" });
  }
});

// GET /api/block/check/:username — Ikki tomonlama bloklash tekshiruvi
router.get("/check/:username", authMiddleware, async (req, res) => {
  const myId = req.user.id;
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

    const { rows } = await pool.query(
      `SELECT blocker_id, blocked_id FROM ${BLOCKED_USERS_TABLE}
       WHERE (blocker_id = $1 AND blocked_id = $2)
          OR (blocker_id = $2 AND blocked_id = $1)`,
      [myId, targetId]
    );

    const iBlockedThem = rows.some((r) => r.blocker_id === myId && r.blocked_id === targetId);
    const theyBlockedMe = rows.some((r) => r.blocker_id === targetId && r.blocked_id === myId);

    res.json({ iBlockedThem, theyBlockedMe });
  } catch (err) {
    console.error("Block check xato:", err);
    res.status(500).json({ message: "Xatolik yuz berdi" });
  }
});

// GET /api/blocked — Bloklangan userlar ro'yxati
router.get("/", authMiddleware, async (req, res) => {
  const blockerId = req.user.id;

  try {
    const { rows } = await pool.query(
      `SELECT u.username, u.avatar, b.created_at
       FROM ${BLOCKED_USERS_TABLE} b
       JOIN ${USERS_TABLE} u ON b.blocked_id = u.id
       WHERE b.blocker_id = $1
       ORDER BY b.created_at DESC`,
      [blockerId]
    );

    res.json(rows);
  } catch (err) {
    console.error("Bloklangan ro'yxatni olishda xato:", err);
    res.status(500).json({ message: "Xatolik yuz berdi" });
  }
});

export default router;
