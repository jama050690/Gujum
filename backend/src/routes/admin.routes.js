import express from "express";
import {
  pool,
  USERS_TABLE,
  CHATS_TABLE,
  MESSAGES_TABLE,
  BLOCKED_USERS_TABLE,
  SPAM_REPORTS_TABLE,
  FRIENDS_TABLE,
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
      newUsersTodayResult,
      recentUsersResult,
      usersResultAll,
    ] = await Promise.all([
      pool.query(`SELECT COUNT(*)::int AS count FROM ${USERS_TABLE}`),
      pool.query(`SELECT COUNT(*)::int AS count FROM ${USERS_TABLE} WHERE role = 'admin'`),
      pool.query(`SELECT COUNT(*)::int AS count FROM ${CHATS_TABLE}`),
      pool.query(`SELECT COUNT(*)::int AS count FROM ${MESSAGES_TABLE}`),
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
      pool.query(
        `SELECT id, username, full_name, email, role, avatar, last_seen
         FROM ${USERS_TABLE}
         ORDER BY CASE WHEN role = 'admin' THEN 0 ELSE 1 END, id DESC`
      ),
    ]);

    res.json({
      stats: {
        users: usersResult.rows[0].count,
        admins: adminsResult.rows[0].count,
        chats: chatsResult.rows[0].count,
        messages: messagesResult.rows[0].count,
        activeToday: newUsersTodayResult.rows[0].count,
      },
      recentUsers: recentUsersResult.rows,
      usersList: usersResultAll.rows,
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

router.delete("/users/:username", adminMiddleware, async (req, res) => {
  const { username } = req.params;

  if (!username) {
    return res.status(400).json({ message: "Username kerak" });
  }

  if (req.user.username === username) {
    return res.status(400).json({ message: "O'zingizni o'chira olmaysiz" });
  }

  const client = await pool.connect();

  try {
    await client.query("BEGIN");

    const userResult = await client.query(
      `SELECT id, username, role FROM ${USERS_TABLE} WHERE username = $1 FOR UPDATE`,
      [username]
    );

    if (userResult.rowCount === 0) {
      await client.query("ROLLBACK");
      return res.status(404).json({ message: "User topilmadi" });
    }

    const targetUser = userResult.rows[0];

    if (targetUser.role === "admin") {
      await client.query("ROLLBACK");
      return res.status(400).json({ message: "Admin userni o'chirish bloklangan" });
    }

    const userId = targetUser.id;

    await client.query(`DELETE FROM push_subscriptions WHERE user_id = $1`, [userId]);
    await client.query(`DELETE FROM ${BLOCKED_USERS_TABLE} WHERE blocker_id = $1 OR blocked_id = $1`, [userId]);
    await client.query(`DELETE FROM ${SPAM_REPORTS_TABLE} WHERE reporter_id = $1 OR reported_id = $1`, [userId]);
    await client.query(`DELETE FROM ${FRIENDS_TABLE} WHERE sender_id = $1 OR receiver_id = $1`, [userId]);

    await client.query(
      `DELETE FROM ${MESSAGES_TABLE}
       WHERE chat_id IN (
         SELECT id FROM ${CHATS_TABLE} WHERE user1_id = $1 OR user2_id = $1
       )`,
      [userId]
    );
    await client.query(
      `DELETE FROM ${CHATS_TABLE} WHERE user1_id = $1 OR user2_id = $1`,
      [userId]
    );

    await client.query(`DELETE FROM ${USERS_TABLE} WHERE id = $1`, [userId]);

    await client.query("COMMIT");
    res.json({ deleted: true, username: targetUser.username });
  } catch (error) {
    await client.query("ROLLBACK");
    console.error("Admin user delete xato:", error);
    res.status(500).json({ message: "Userni o'chirishda xatolik yuz berdi" });
  } finally {
    client.release();
  }
});

export default router;
