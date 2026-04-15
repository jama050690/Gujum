import express from "express";
import { pool, USERS_TABLE, GROUPS_TABLE, GROUP_MEMBERS_TABLE, GROUP_MESSAGES_TABLE } from "../config/database.js";


const router = express.Router();

// POST /api/groups
router.post("/", async (req, res) => {
  const { name, username, avatar, allow_download } = req.body;

  if (!name || !username) {
    return res.status(400).json({ message: "Guruh nomi va username kerak" });
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

    const groupResult = await pool.query(
      `INSERT INTO ${GROUPS_TABLE} (name, avatar, created_by, allow_download) VALUES ($1, $2, $3, $4) RETURNING id, name, avatar, allow_download, created_at`,
      [name, avatar || null, userId, allow_download || false]
    );

    const group = groupResult.rows[0];

    await pool.query(
      `INSERT INTO ${GROUP_MEMBERS_TABLE} (group_id, user_id, role) VALUES ($1, $2, 'admin')`,
      [group.id, userId]
    );

    console.log(`Yangi guruh yaratildi: ${name} (ID: ${group.id})${avatar ? ', avatar: ' + avatar : ''}`);

    res.json({
      message: "Guruh yaratildi",
      group: {
        id: group.id,
        name: group.name,
        avatar: group.avatar,
        type: "group",
        allow_download: group.allow_download,
        memberCount: 1,
        created_at: group.created_at
      }
    });
  } catch (err) {
    console.error("Guruh yaratishda xato:", err);
    res.status(500).json({ message: "Guruh yaratishda xatolik" });
  }
});

// GET /api/groups
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
      SELECT g.id, g.name, g.avatar, g.allow_download, g.created_at,
             (SELECT COUNT(*) FROM ${GROUP_MEMBERS_TABLE} WHERE group_id = g.id) as member_count
      FROM ${GROUPS_TABLE} g
      JOIN ${GROUP_MEMBERS_TABLE} gm ON g.id = gm.group_id
      WHERE gm.user_id = $1
      ORDER BY g.created_at DESC
    `, [userId]);

    const groups = rows.map(g => ({
      ...g,
      type: "group",
      memberCount: parseInt(g.member_count)
    }));

    res.json(groups);
  } catch (err) {
    console.error("Guruhlarni olishda xato:", err);
    res.status(500).json({ message: "Xatolik yuz berdi" });
  }
});

// GET /api/groups/:id/members
router.get("/:id/members", async (req, res) => {
  const { id } = req.params;

  try {
    const { rows } = await pool.query(`
      SELECT u.id, u.username, u.avatar, gm.role, gm.joined_at
      FROM ${GROUP_MEMBERS_TABLE} gm
      JOIN ${USERS_TABLE} u ON gm.user_id = u.id
      WHERE gm.group_id = $1
      ORDER BY gm.role DESC, gm.joined_at ASC
    `, [id]);

    res.json(rows);
  } catch (err) {
    console.error("Guruh a'zolarini olishda xato:", err);
    res.status(500).json({ message: "Xatolik yuz berdi" });
  }
});

// POST /api/groups/:id/members
router.post("/:id/members", async (req, res) => {
  const { id } = req.params;
  const { userIds } = req.body;

  if (!userIds || !Array.isArray(userIds) || userIds.length === 0) {
    return res.status(400).json({ message: "userIds kerak (array)" });
  }

  try {
    const groupResult = await pool.query(
      `SELECT id FROM ${GROUPS_TABLE} WHERE id = $1`,
      [id]
    );

    if (groupResult.rowCount === 0) {
      return res.status(404).json({ message: "Guruh topilmadi" });
    }

    let addedCount = 0;
    for (const userId of userIds) {
      try {
        await pool.query(
          `INSERT INTO ${GROUP_MEMBERS_TABLE} (group_id, user_id, role) VALUES ($1, $2, 'member')
           ON CONFLICT (group_id, user_id) DO NOTHING`,
          [id, userId]
        );
        addedCount++;
      } catch (err) {
        console.error(`User ${userId} ni qo'shishda xato:`, err);
      }
    }

    console.log(`Guruhga ${addedCount} ta a'zo qo'shildi (Group ID: ${id})`);

    res.json({
      message: `${addedCount} ta a'zo qo'shildi`,
      addedCount
    });
  } catch (err) {
    console.error("Guruhga a'zo qo'shishda xato:", err);
    res.status(500).json({ message: "Xatolik yuz berdi" });
  }
});

// GET /api/groups/:id/messages
router.get("/:id/messages", async (req, res) => {
  const { id } = req.params;

  try {
    const { rows } = await pool.query(`
      SELECT gm.id, gm.content, gm.image, gm.audio, gm.created_at,
             u.username, u.avatar
      FROM ${GROUP_MESSAGES_TABLE} gm
      JOIN ${USERS_TABLE} u ON gm.sender_id = u.id
      WHERE gm.group_id = $1
      ORDER BY gm.created_at ASC
    `, [id]);

    res.json(rows);
  } catch (err) {
    console.error("Guruh xabarlarini olishda xato:", err);
    res.status(500).json({ message: "Xatolik yuz berdi" });
  }
});

// DELETE /api/groups/:id
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

    // Faqat admin yoki guruh yaratuvchisi o'chira oladi
    const memberResult = await pool.query(
      `SELECT role FROM ${GROUP_MEMBERS_TABLE} WHERE group_id = $1 AND user_id = $2`,
      [id, userId]
    );

    const groupOwner = await pool.query(
      `SELECT created_by FROM ${GROUPS_TABLE} WHERE id = $1`,
      [id]
    );

    const isAdmin = memberResult.rowCount > 0 && memberResult.rows[0].role === "admin";
    const isOwner = groupOwner.rowCount > 0 && groupOwner.rows[0].created_by === userId;

    if (!isAdmin && !isOwner) {
      return res.status(403).json({ message: "Faqat admin guruhni o'chira oladi" });
    }

    // Xabarlar, a'zolar, keyin guruhni o'chirish
    await pool.query(`DELETE FROM ${GROUP_MESSAGES_TABLE} WHERE group_id = $1`, [id]);
    await pool.query(`DELETE FROM ${GROUP_MEMBERS_TABLE} WHERE group_id = $1`, [id]);
    await pool.query(`DELETE FROM ${GROUPS_TABLE} WHERE id = $1`, [id]);

    console.log(`Guruh o'chirildi (ID: ${id})`);
    res.json({ message: "Guruh o'chirildi" });
  } catch (err) {
    console.error("Guruhni o'chirishda xato:", err);
    res.status(500).json({ message: "Xatolik yuz berdi" });
  }
});

export default router;
