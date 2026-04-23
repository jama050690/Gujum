import express from "express";
import {
  pool,
  USERS_TABLE,
  MESSAGES_TABLE,
  CHATS_TABLE,
} from "../config/database.js";
import { authMiddleware } from "../middleware/auth.js";

const router = express.Router();

// GET /api/calls/history
router.get("/calls/history", async (req, res) => {
  const { username } = req.query;
  if (!username) return res.status(400).json({ message: "username kerak" });

  try {
    const userResult = await pool.query(
      `SELECT id FROM ${USERS_TABLE} WHERE username = $1`,
      [username],
    );

    if (userResult.rowCount === 0) {
      return res.json([]);
    }

    const userId = userResult.rows[0].id;

    const { rows } = await pool.query(
      `
      SELECT
        m.id,
        m.content,
        m.created_at,
        sender.username AS caller,
        peer.username AS "peerUsername",
        peer.full_name AS "peerFullName",
        peer.avatar AS "peerAvatar"
      FROM ${MESSAGES_TABLE} m
      JOIN ${CHATS_TABLE} c ON c.id = m.chat_id
      JOIN ${USERS_TABLE} sender ON sender.id = m.sender_id
      JOIN ${USERS_TABLE} peer ON peer.id = CASE
        WHEN c.user1_id = $1 THEN c.user2_id
        ELSE c.user1_id
      END
      WHERE (c.user1_id = $1 OR c.user2_id = $1)
        AND m.content LIKE '__CALL:%__'
      ORDER BY m.created_at DESC
      `,
      [userId],
    );

    return res.json(rows);
  } catch (err) {
    console.error("Call history olishda xato:", err);
    return res.status(500).json({ message: "Xatolik yuz berdi" });
  }
});

// GET /api/messages
router.get("/messages", async (req, res) => {
  const { user1, user2 } = req.query;

  // Agar user1 va user2 berilgan bo'lsa - private chat
  if (user1 && user2) {
    try {
      const user1Result = await pool.query(
        `SELECT id FROM ${USERS_TABLE} WHERE username = $1`,
        [user1]
      );
      const user2Result = await pool.query(
        `SELECT id FROM ${USERS_TABLE} WHERE username = $1`,
        [user2]
      );

      if (user1Result.rowCount === 0 || user2Result.rowCount === 0) {
        return res.json([]);
      }

      const user1Id = user1Result.rows[0].id;
      const user2Id = user2Result.rows[0].id;

      const [u1, u2] = user1Id < user2Id ? [user1Id, user2Id] : [user2Id, user1Id];
      const chatResult = await pool.query(
        `SELECT id FROM ${CHATS_TABLE} WHERE user1_id = $1 AND user2_id = $2`,
        [u1, u2]
      );

      if (chatResult.rowCount === 0) {
        return res.json([]);
      }

      const chatId = chatResult.rows[0].id;

      // Avval o'qilmagan xabarlarni read qilamiz
      await pool.query(
        `UPDATE ${MESSAGES_TABLE}
         SET is_read = TRUE, read_at = NOW()
         WHERE chat_id = $1 AND sender_id = $2 AND COALESCE(is_read, FALSE) = FALSE`,
        [chatId, user2Id]
      );

      const { rows } = await pool.query(
        `SELECT m.id, m.content, m.image, m.audio, m.video, m.is_read, m.created_at, m.reply_to_username, m.reply_to_content, u.username, u.avatar, u.full_name
         FROM ${MESSAGES_TABLE} m
         JOIN ${USERS_TABLE} u ON m.sender_id = u.id
         WHERE m.chat_id = $1
         ORDER BY m.created_at ASC`,
        [chatId],
      );

      return res.json(rows);
    } catch (err) {
      console.error("Xabarlarni olishda xato:", err);
      return res.status(500).json({ message: "Xatolik yuz berdi" });
    }
  }

  // Aks holda barcha xabarlar
  const { rows } = await pool.query(
    `SELECT m.id, m.content, m.image, m.audio, m.video, m.created_at, u.username, u.avatar, u.full_name
     FROM ${MESSAGES_TABLE} m
     JOIN ${USERS_TABLE} u ON m.sender_id = u.id
     ORDER BY m.created_at ASC`,
  );
  res.json(rows);
});

// POST /api/messages
router.post("/messages", authMiddleware, async (req, res) => {
  const senderUsername = req.user?.username;
  const {
    receiver,
    message = "",
    image = null,
    audio = null,
    video = null,
    replyTo,
  } = req.body || {};

  const text = typeof message === "string" ? message.trim() : "";
  const imagePath =
    typeof image === "string" && image.trim() ? image.trim() : null;
  const audioPath =
    typeof audio === "string" && audio.trim() ? audio.trim() : null;
  const videoPath =
    typeof video === "string" && video.trim() ? video.trim() : null;

  if (
    !senderUsername ||
    !receiver ||
    (!text && !imagePath && !audioPath && !videoPath)
  ) {
    return res.status(400).json({ message: "receiver va xabar kerak" });
  }

  try {
    const senderResult = await pool.query(
      `SELECT id, username, avatar, full_name FROM ${USERS_TABLE} WHERE username = $1`,
      [senderUsername],
    );
    const receiverResult = await pool.query(
      `SELECT id FROM ${USERS_TABLE} WHERE username = $1`,
      [receiver],
    );

    if (senderResult.rowCount === 0 || receiverResult.rowCount === 0) {
      return res.status(404).json({ message: "Foydalanuvchi topilmadi" });
    }

    const sender = senderResult.rows[0];
    const senderId = sender.id;
    const receiverId = receiverResult.rows[0].id;
    const [user1Id, user2Id] =
      senderId < receiverId ? [senderId, receiverId] : [receiverId, senderId];

    let chatResult = await pool.query(
      `SELECT id FROM ${CHATS_TABLE} WHERE user1_id = $1 AND user2_id = $2`,
      [user1Id, user2Id],
    );

    let chatId;
    if (chatResult.rowCount === 0) {
      const newChat = await pool.query(
        `INSERT INTO ${CHATS_TABLE} (user1_id, user2_id) VALUES ($1, $2) RETURNING id`,
        [user1Id, user2Id],
      );
      chatId = newChat.rows[0].id;
    } else {
      chatId = chatResult.rows[0].id;
    }

    const msgResult = await pool.query(
      `INSERT INTO ${MESSAGES_TABLE} (chat_id, sender_id, content, image, audio, video, reply_to_username, reply_to_content)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       RETURNING id, created_at, is_read`,
      [
        chatId,
        senderId,
        text,
        imagePath,
        audioPath,
        videoPath,
        replyTo?.username || null,
        replyTo?.content || null,
      ],
    );

    return res.status(201).json({
      id: msgResult.rows[0].id,
      created_at: msgResult.rows[0].created_at,
      is_read: msgResult.rows[0].is_read,
      username: sender.username,
      full_name: sender.full_name,
      avatar: sender.avatar,
      receiver,
      content: text,
      image: imagePath,
      audio: audioPath,
      video: videoPath,
      reply_to_username: replyTo?.username || null,
      reply_to_content: replyTo?.content || null,
    });
  } catch (err) {
    console.error("Xabar yuborishda xato:", err);
    return res.status(500).json({ message: "Xatolik yuz berdi" });
  }
});

// GET /api/inbox
router.get("/inbox", async (req, res) => {
  const { username } = req.query;
  if (!username) return res.status(400).json({ message: "username kerak" });

  try {
    const userResult = await pool.query(
      `SELECT id FROM ${USERS_TABLE} WHERE username = $1`,
      [username]
    );

    if (userResult.rowCount === 0) {
      return res.json([]);
    }

    const userId = userResult.rows[0].id;

    // Get chats with last message info using LATERAL join
    const { rows } = await pool.query(`
      SELECT
        u.username as sender,
        u.avatar,
        u.full_name as "senderFullName",
        u.last_seen as "lastActive",
        lm.content as lastContent,
        lm.image as lastImage,
        lm.audio as lastAudio,
        lm.video as lastVideo,
        lm.created_at as lastMessageTime,
        COALESCE(uc.unread_count, 0) as unreadCount
      FROM ${CHATS_TABLE} c
      JOIN ${USERS_TABLE} u ON (
        CASE
          WHEN c.user1_id = $1 THEN c.user2_id = u.id
          ELSE c.user1_id = u.id
        END
      )
      LEFT JOIN LATERAL (
        SELECT content, image, audio, video, created_at
        FROM ${MESSAGES_TABLE}
        WHERE chat_id = c.id
        ORDER BY created_at DESC
        LIMIT 1
      ) lm ON true
      LEFT JOIN LATERAL (
        SELECT COUNT(*)::int as unread_count
        FROM ${MESSAGES_TABLE} um
        WHERE um.chat_id = c.id
          AND um.sender_id <> $1
          AND COALESCE(um.is_read, FALSE) = FALSE
      ) uc ON true
      WHERE c.user1_id = $1 OR c.user2_id = $1
      ORDER BY lm.created_at DESC NULLS LAST
    `,
      [userId],
    );

    res.json(rows);
  } catch (err) {
    console.error("Inbox olishda xato:", err);
    res.status(500).json({ message: "Xatolik yuz berdi" });
  }
});

// POST /api/messages/mark-read
router.post("/messages/mark-read", async (req, res) => {
  const { username, chatWith } = req.body;
  if (!username || !chatWith) {
    return res.status(400).json({ message: "username va chatWith kerak" });
  }

  try {
    const userResult = await pool.query(
      `SELECT id FROM ${USERS_TABLE} WHERE username = $1`,
      [username]
    );
    const peerResult = await pool.query(
      `SELECT id FROM ${USERS_TABLE} WHERE username = $1`,
      [chatWith]
    );

    if (userResult.rowCount === 0 || peerResult.rowCount === 0) {
      return res.json({ updated: 0 });
    }

    const userId = userResult.rows[0].id;
    const peerId = peerResult.rows[0].id;
    const [u1, u2] = userId < peerId ? [userId, peerId] : [peerId, userId];

    const chatResult = await pool.query(
      `SELECT id FROM ${CHATS_TABLE} WHERE user1_id = $1 AND user2_id = $2`,
      [u1, u2]
    );

    if (chatResult.rowCount === 0) {
      return res.json({ updated: 0 });
    }

    const chatId = chatResult.rows[0].id;
    const updateResult = await pool.query(
      `UPDATE ${MESSAGES_TABLE}
       SET is_read = TRUE, read_at = NOW()
       WHERE chat_id = $1 AND sender_id = $2 AND COALESCE(is_read, FALSE) = FALSE`,
      [chatId, peerId]
    );

    return res.json({ updated: updateResult.rowCount });
  } catch (err) {
    console.error("Xabarlarni read qilishda xato:", err);
    return res.status(500).json({ message: "Xatolik yuz berdi" });
  }
});

// DELETE /api/messages/:id
router.delete("/messages/:id", authMiddleware, async (req, res) => {
  const { id } = req.params;

  try {
    const existing = await pool.query(
      `SELECT sender_id FROM ${MESSAGES_TABLE} WHERE id = $1`,
      [id],
    );

    if (existing.rowCount === 0) {
      return res.status(404).json({ message: "Xabar topilmadi" });
    }

    if (existing.rows[0].sender_id !== req.user.id) {
      return res.status(403).json({ message: "Bu xabarni o'chirib bo'lmaydi" });
    }

    const result = await pool.query(
      `DELETE FROM ${MESSAGES_TABLE} WHERE id = $1 RETURNING id`,
      [id],
    );

    return res.json({ deleted: true, id: Number(id) });
  } catch (err) {
    console.error("Xabarni o'chirishda xato:", err);
    return res.status(500).json({ message: "Xatolik yuz berdi" });
  }
});

export default router;
