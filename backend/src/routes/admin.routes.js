import express from "express";
import {
  pool,
  USERS_TABLE,
  CHATS_TABLE,
  MESSAGES_TABLE,
  GROUPS_TABLE,
  CHANNELS_TABLE,
} from "../config/database.js";
import { adminMiddleware } from "../middleware/auth.js";

const router = express.Router();

router.get("/dashboard", adminMiddleware, async (req, res) => {
  try {
    const [
      usersResult,
      adminsResult,
      chatsResult,
      messagesResult,
      groupsResult,
      channelsResult,
      newUsersTodayResult,
      recentUsersResult,
    ] = await Promise.all([
      pool.query(`SELECT COUNT(*)::int AS count FROM ${USERS_TABLE}`),
      pool.query(`SELECT COUNT(*)::int AS count FROM ${USERS_TABLE} WHERE role = 'admin'`),
      pool.query(`SELECT COUNT(*)::int AS count FROM ${CHATS_TABLE}`),
      pool.query(`SELECT COUNT(*)::int AS count FROM ${MESSAGES_TABLE}`),
      pool.query(`SELECT COUNT(*)::int AS count FROM ${GROUPS_TABLE}`),
      pool.query(`SELECT COUNT(*)::int AS count FROM ${CHANNELS_TABLE}`),
      pool.query(
        `SELECT COUNT(*)::int AS count
         FROM ${USERS_TABLE}
         WHERE DATE(COALESCE(last_seen, NOW())) = CURRENT_DATE`
      ),
      pool.query(
        `SELECT username, full_name, email, role, avatar, last_seen
         FROM ${USERS_TABLE}
         ORDER BY id DESC
         LIMIT 8`
      ),
    ]);

    res.json({
      stats: {
        users: usersResult.rows[0].count,
        admins: adminsResult.rows[0].count,
        chats: chatsResult.rows[0].count,
        messages: messagesResult.rows[0].count,
        groups: groupsResult.rows[0].count,
        channels: channelsResult.rows[0].count,
        activeToday: newUsersTodayResult.rows[0].count,
      },
      recentUsers: recentUsersResult.rows,
      session: {
        username: req.user.username,
        role: req.user.role,
      },
    });
  } catch (error) {
    console.error("Admin dashboard xato:", error);
    res.status(500).json({ message: "Admin dashboard ma'lumotlarini olib bo'lmadi" });
  }
});

export default router;
