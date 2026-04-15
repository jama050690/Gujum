import express from "express";
import { pool, USERS_TABLE, CHANNELS_TABLE, CHANNEL_SUBSCRIBERS_TABLE, CHANNEL_MESSAGES_TABLE } from "../config/database.js";

const router = express.Router();

// POST /api/channels
router.post("/", async (req, res) => {
  const { name, description, username, avatar, allow_download } = req.body;

  if (!name || !username) {
    return res.status(400).json({ message: "Kanal nomi va username kerak" });
  }

  try {
    const userResult = await pool.query(
      `SELECT id FROM ${USERS_TABLE} WHERE username = $1`,
      [username]
    );

    if (userResult.rowCount === 0) {
      return res.status(404).json({ message: "User topilmadi" });
    }

    const userId = userResult.rows[0].id;

    const channelResult = await pool.query(
      `INSERT INTO ${CHANNELS_TABLE} (name, description, avatar, created_by, allow_download) VALUES ($1, $2, $3, $4, $5) RETURNING id, name, description, avatar, allow_download, created_at`,
      [name, description || "", avatar || null, userId, allow_download || false]
    );

    const channel = channelResult.rows[0];

    await pool.query(
      `INSERT INTO ${CHANNEL_SUBSCRIBERS_TABLE} (channel_id, user_id) VALUES ($1, $2)`,
      [channel.id, userId]
    );

    console.log(`Yangi kanal yaratildi: ${name} (ID: ${channel.id})${avatar ? ', avatar: ' + avatar : ''}`);

    res.json({
      message: "Kanal yaratildi",
      channel: {
        id: channel.id,
        name: channel.name,
        description: channel.description,
        avatar: channel.avatar,
        type: "channel",
        allow_download: channel.allow_download,
        subscriberCount: 1,
        created_at: channel.created_at
      }
    });
  } catch (err) {
    console.error("Kanal yaratishda xato:", err);
    res.status(500).json({ message: "Kanal yaratishda xatolik" });
  }
});

// GET /api/channels
router.get("/", async (req, res) => {
  const { username } = req.query;

  if (!username) {
    return res.status(400).json({ message: "username kerak" });
  }

  try {
    const userResult = await pool.query(
      `SELECT id FROM ${USERS_TABLE} WHERE username = $1`,
      [username]
    );

    if (userResult.rowCount === 0) {
      return res.json([]);
    }

    const userId = userResult.rows[0].id;

    const { rows } = await pool.query(`
      SELECT c.id, c.name, c.description, c.avatar, c.allow_download, c.created_at,
             (SELECT COUNT(*) FROM ${CHANNEL_SUBSCRIBERS_TABLE} WHERE channel_id = c.id) as subscriber_count
      FROM ${CHANNELS_TABLE} c
      JOIN ${CHANNEL_SUBSCRIBERS_TABLE} cs ON c.id = cs.channel_id
      WHERE cs.user_id = $1
      ORDER BY c.created_at DESC
    `, [userId]);

    const channels = rows.map(c => ({
      ...c,
      type: "channel",
      subscriberCount: parseInt(c.subscriber_count)
    }));

    res.json(channels);
  } catch (err) {
    console.error("Kanallarni olishda xato:", err);
    res.status(500).json({ message: "Xatolik yuz berdi" });
  }
});

// GET /api/channels/:id/subscribers
router.get("/:id/subscribers", async (req, res) => {
  const { id } = req.params;

  try {
    const { rows } = await pool.query(`
      SELECT u.id, u.username, u.avatar, cs.subscribed_at
      FROM ${CHANNEL_SUBSCRIBERS_TABLE} cs
      JOIN ${USERS_TABLE} u ON cs.user_id = u.id
      WHERE cs.channel_id = $1
      ORDER BY cs.subscribed_at ASC
    `, [id]);

    res.json(rows);
  } catch (err) {
    console.error("Kanal obunachilarini olishda xato:", err);
    res.status(500).json({ message: "Xatolik yuz berdi" });
  }
});

// POST /api/channels/:id/subscribers
router.post("/:id/subscribers", async (req, res) => {
  const { id } = req.params;
  const { userIds } = req.body;

  if (!userIds || !Array.isArray(userIds) || userIds.length === 0) {
    return res.status(400).json({ message: "userIds kerak (array)" });
  }

  try {
    const channelResult = await pool.query(
      `SELECT id FROM ${CHANNELS_TABLE} WHERE id = $1`,
      [id]
    );

    if (channelResult.rowCount === 0) {
      return res.status(404).json({ message: "Kanal topilmadi" });
    }

    let addedCount = 0;
    for (const userId of userIds) {
      try {
        await pool.query(
          `INSERT INTO ${CHANNEL_SUBSCRIBERS_TABLE} (channel_id, user_id) VALUES ($1, $2)
           ON CONFLICT (channel_id, user_id) DO NOTHING`,
          [id, userId]
        );
        addedCount++;
      } catch (err) {
        console.error(`User ${userId} ni qo'shishda xato:`, err);
      }
    }

    console.log(`Kanalga ${addedCount} ta obunachi qo'shildi (Channel ID: ${id})`);

    res.json({
      message: `${addedCount} ta obunachi qo'shildi`,
      addedCount
    });
  } catch (err) {
    console.error("Kanalga obunachi qo'shishda xato:", err);
    res.status(500).json({ message: "Xatolik yuz berdi" });
  }
});

// GET /api/channels/:id/messages
router.get("/:id/messages", async (req, res) => {
  const { id } = req.params;

  try {
    const { rows } = await pool.query(`
      SELECT cm.id, cm.content, cm.image, cm.audio, cm.created_at,
             u.username, u.avatar
      FROM ${CHANNEL_MESSAGES_TABLE} cm
      JOIN ${USERS_TABLE} u ON cm.sender_id = u.id
      WHERE cm.channel_id = $1
      ORDER BY cm.created_at ASC
    `, [id]);

    res.json(rows);
  } catch (err) {
    console.error("Kanal xabarlarini olishda xato:", err);
    res.status(500).json({ message: "Xatolik yuz berdi" });
  }
});

// DELETE /api/channels/:id
router.delete("/:id", async (req, res) => {
  const { id } = req.params;
  const { username } = req.body;

  if (!username) {
    return res.status(400).json({ message: "username kerak" });
  }

  try {
    const userResult = await pool.query(
      `SELECT id FROM ${USERS_TABLE} WHERE username = $1`,
      [username]
    );

    if (userResult.rowCount === 0) {
      return res.status(404).json({ message: "User topilmadi" });
    }

    const userId = userResult.rows[0].id;

    // Faqat yaratuvchi o'chira oladi
    const channelResult = await pool.query(
      `SELECT created_by FROM ${CHANNELS_TABLE} WHERE id = $1`,
      [id]
    );

    if (channelResult.rowCount === 0) {
      return res.status(404).json({ message: "Kanal topilmadi" });
    }

    if (channelResult.rows[0].created_by !== userId) {
      return res.status(403).json({ message: "Faqat kanal egasi o'chira oladi" });
    }

    // Obunachilarni o'chirish, keyin kanalni
    await pool.query(`DELETE FROM ${CHANNEL_SUBSCRIBERS_TABLE} WHERE channel_id = $1`, [id]);
    await pool.query(`DELETE FROM ${CHANNELS_TABLE} WHERE id = $1`, [id]);

    console.log(`Kanal o'chirildi (ID: ${id})`);
    res.json({ message: "Kanal o'chirildi" });
  } catch (err) {
    console.error("Kanalni o'chirishda xato:", err);
    res.status(500).json({ message: "Xatolik yuz berdi" });
  }
});

export default router;
