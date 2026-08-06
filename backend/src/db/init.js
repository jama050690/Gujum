import {
  pool,
  USERS_TABLE,
  CHATS_TABLE,
  MESSAGES_TABLE,
  GROUPS_TABLE,
  GROUP_MEMBERS_TABLE,
  GROUP_MESSAGES_TABLE,
  CHANNELS_TABLE,
  CHANNEL_SUBSCRIBERS_TABLE,
  CHANNEL_MESSAGES_TABLE,
  BLOCKED_USERS_TABLE,
  SPAM_REPORTS_TABLE,
  FRIENDS_TABLE,
} from "../config/database.js";
import argon2 from "argon2";

async function initUsersTable() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS ${USERS_TABLE} (
      id SERIAL PRIMARY KEY,
      username VARCHAR(25) UNIQUE NOT NULL,
      email VARCHAR(35) NOT NULL,
      password_hash TEXT NOT NULL,
      age INT NOT NULL,
      gender BOOLEAN NOT NULL,
      avatar TEXT
    );
  `);
  await pool.query(`
    ALTER TABLE ${USERS_TABLE} ADD COLUMN IF NOT EXISTS avatar TEXT;
  `);
  await pool.query(`
    ALTER TABLE ${USERS_TABLE} ADD COLUMN IF NOT EXISTS full_name VARCHAR(50);
  `);
  await pool.query(`
    ALTER TABLE ${USERS_TABLE} ADD COLUMN IF NOT EXISTS phone VARCHAR(20);
  `);
  await pool.query(`
    ALTER TABLE ${USERS_TABLE} ADD COLUMN IF NOT EXISTS birthday DATE;
  `);
  // Audit uchun: raqam SIM tanlagichidan olindimi (TRUE) yoki qo'lda
  // yozildimi (FALSE). Hech qanday mantiqqa ta'sir qilmaydi — keyinchalik
  // suiiste'molni tekshirish kerak bo'lsa shu maydonga qaraladi. Keyin
  // to'ldirib bo'lmaydi, shuning uchun hozirdan yig'ib boramiz.
  await pool.query(`
    ALTER TABLE ${USERS_TABLE} ADD COLUMN IF NOT EXISTS phone_from_sim BOOLEAN;
  `);
  await pool.query(`
    ALTER TABLE ${USERS_TABLE} ADD COLUMN IF NOT EXISTS phone_set_at TIMESTAMPTZ;
  `);
  await pool.query(`
    ALTER TABLE ${USERS_TABLE} ADD COLUMN IF NOT EXISTS bio VARCHAR(70);
  `);
  await pool.query(`
    ALTER TABLE ${USERS_TABLE} ADD COLUMN IF NOT EXISTS last_seen TIMESTAMP;
  `);
  await pool.query(`
    ALTER TABLE ${USERS_TABLE} ADD COLUMN IF NOT EXISTS is_online BOOLEAN DEFAULT FALSE;
  `);
  await pool.query(`
    ALTER TABLE ${USERS_TABLE} ADD COLUMN IF NOT EXISTS role VARCHAR(20) NOT NULL DEFAULT 'user';
  `);
  // Raqamlar turli formatlarda saqlanadi (+998 90 123 45 67, 901234567, ...),
  // shuning uchun indeks normallashtirilgan oxirgi 9 raqam ustiga quriladi —
  // kontaktlarni solishtirish ham aynan shu ko'rinishda ishlaydi.
  // Bazada allaqachon takrorlanuvchi raqamlar bo'lsa indeks qurilmaydi:
  // bu holda server ishga tushishi to'xtamasligi kerak, faqat ogohlantiramiz.
  try {
    await pool.query(`
      CREATE UNIQUE INDEX IF NOT EXISTS ${USERS_TABLE}_phone_norm_uniq
      ON ${USERS_TABLE} ((RIGHT(REGEXP_REPLACE(phone, '\\D', '', 'g'), 9)))
      WHERE phone IS NOT NULL AND phone <> ''
    `);
  } catch (e) {
    console.warn(
      `[DB] phone unique indeksi qurilmadi (ehtimol takrorlanuvchi raqamlar bor): ${e.message}`,
    );
  }
  // Akkaunt o'chirilganda a'zolari bor guruh/kanal egasiz qoladi — shuning
  // uchun created_by NULL bo'la olishi kerak. Jadval NOT NULL bilan
  // yaratilgan bo'lsa cheklovni olib tashlaymiz.
  for (const table of [GROUPS_TABLE, CHANNELS_TABLE]) {
    try {
      await pool.query(`ALTER TABLE ${table} ALTER COLUMN created_by DROP NOT NULL`);
    } catch (e) {
      console.warn(`[DB] ${table}.created_by NOT NULL olib tashlanmadi: ${e.message}`);
    }
  }
  console.log("Users table tayyor");
}

async function ensureAdminUser() {
  const username = String(process.env.ADMIN_USERNAME || "").trim();
  const email = String(process.env.ADMIN_EMAIL || "").trim();
  const password = String(process.env.ADMIN_PASSWORD || "").trim();
  const fullName = String(process.env.ADMIN_FULL_NAME || "Administrator").trim();

  if (!username || !email || !password) {
    console.log("Admin seed o'tkazib yuborildi: ADMIN_* env topilmadi");
    return;
  }

  const existing = await pool.query(
    `SELECT id, role FROM ${USERS_TABLE} WHERE LOWER(username) = LOWER($1) LIMIT 1`,
    [username]
  );

  const passwordHash = await argon2.hash(password);

  if (existing.rowCount > 0) {
    await pool.query(
      `UPDATE ${USERS_TABLE}
       SET role = 'admin',
           email = $1,
           password_hash = $2,
           full_name = COALESCE(NULLIF(full_name, ''), $3)
       WHERE id = $4`,
      [email, passwordHash, fullName, existing.rows[0].id]
    );
    console.log(`Admin user yangilandi: ${username}`);
    return;
  }

  await pool.query(
    `INSERT INTO ${USERS_TABLE} (username, email, password_hash, age, gender, full_name, role)
     VALUES ($1, $2, $3, $4, $5, $6, 'admin')`,
    [username, email, passwordHash, 18, true, fullName || username]
  );
  console.log(`Admin user yaratildi: ${username}`);
}

async function initChatsTable() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS ${CHATS_TABLE} (
      id SERIAL PRIMARY KEY,
      user1_id INT NOT NULL REFERENCES ${USERS_TABLE}(id),
      user2_id INT NOT NULL REFERENCES ${USERS_TABLE}(id),
      created_at TIMESTAMP DEFAULT NOW(),
      UNIQUE(user1_id, user2_id)
    );
  `);
  console.log("Chat_messages table tayyor");
}

async function initMessagesTable() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS ${MESSAGES_TABLE} (
      id SERIAL PRIMARY KEY,
      chat_id INT NOT NULL REFERENCES ${CHATS_TABLE}(id),
      sender_id INT NOT NULL REFERENCES ${USERS_TABLE}(id),
      content TEXT,
      image TEXT,
      audio TEXT,
      is_read BOOLEAN DEFAULT FALSE,
      read_at TIMESTAMP,
      created_at TIMESTAMP DEFAULT NOW()
    );
  `);
  await pool.query(`
    ALTER TABLE ${MESSAGES_TABLE} ADD COLUMN IF NOT EXISTS audio TEXT;
  `);
  await pool.query(`
    ALTER TABLE ${MESSAGES_TABLE} ADD COLUMN IF NOT EXISTS is_read BOOLEAN DEFAULT FALSE;
  `);
  await pool.query(`
    ALTER TABLE ${MESSAGES_TABLE} ADD COLUMN IF NOT EXISTS read_at TIMESTAMP;
  `);
  await pool.query(`
    ALTER TABLE ${MESSAGES_TABLE} ADD COLUMN IF NOT EXISTS reply_to_username VARCHAR(25);
  `);
  await pool.query(`
    ALTER TABLE ${MESSAGES_TABLE} ADD COLUMN IF NOT EXISTS reply_to_content TEXT;
  `);
  await pool.query(`
    ALTER TABLE ${MESSAGES_TABLE} ADD COLUMN IF NOT EXISTS video TEXT;
  `);
  console.log("Messages table tayyor");
}

async function initGroupsTable() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS ${GROUPS_TABLE} (
      id SERIAL PRIMARY KEY,
      name VARCHAR(100) NOT NULL,
      avatar TEXT,
      created_by INT NOT NULL REFERENCES ${USERS_TABLE}(id),
      created_at TIMESTAMP DEFAULT NOW()
    );
  `);
  await pool.query(`
    ALTER TABLE ${GROUPS_TABLE} ADD COLUMN IF NOT EXISTS allow_download BOOLEAN DEFAULT FALSE;
  `);
  console.log("Groups table tayyor");
}

async function initGroupMembersTable() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS ${GROUP_MEMBERS_TABLE} (
      id SERIAL PRIMARY KEY,
      group_id INT NOT NULL REFERENCES ${GROUPS_TABLE}(id) ON DELETE CASCADE,
      user_id INT NOT NULL REFERENCES ${USERS_TABLE}(id),
      role VARCHAR(20) DEFAULT 'member',
      joined_at TIMESTAMP DEFAULT NOW(),
      UNIQUE(group_id, user_id)
    );
  `);
  console.log("Group_members table tayyor");
}

async function initGroupMessagesTable() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS ${GROUP_MESSAGES_TABLE} (
      id SERIAL PRIMARY KEY,
      group_id INT NOT NULL REFERENCES ${GROUPS_TABLE}(id) ON DELETE CASCADE,
      sender_id INT NOT NULL REFERENCES ${USERS_TABLE}(id),
      content TEXT,
      image TEXT,
      audio TEXT,
      created_at TIMESTAMP DEFAULT NOW()
    );
  `);
  console.log("Group_messages table tayyor");
}

async function initChannelsTable() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS ${CHANNELS_TABLE} (
      id SERIAL PRIMARY KEY,
      name VARCHAR(100) NOT NULL,
      description TEXT,
      avatar TEXT,
      created_by INT NOT NULL REFERENCES ${USERS_TABLE}(id),
      created_at TIMESTAMP DEFAULT NOW()
    );
  `);
  await pool.query(`
    ALTER TABLE ${CHANNELS_TABLE} ADD COLUMN IF NOT EXISTS allow_download BOOLEAN DEFAULT FALSE;
  `);
  console.log("Channels table tayyor");
}

async function initChannelSubscribersTable() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS ${CHANNEL_SUBSCRIBERS_TABLE} (
      id SERIAL PRIMARY KEY,
      channel_id INT NOT NULL REFERENCES ${CHANNELS_TABLE}(id) ON DELETE CASCADE,
      user_id INT NOT NULL REFERENCES ${USERS_TABLE}(id),
      subscribed_at TIMESTAMP DEFAULT NOW(),
      UNIQUE(channel_id, user_id)
    );
  `);
  console.log("Channel_subscribers table tayyor");
}

async function initChannelMessagesTable() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS ${CHANNEL_MESSAGES_TABLE} (
      id SERIAL PRIMARY KEY,
      channel_id INT NOT NULL REFERENCES ${CHANNELS_TABLE}(id) ON DELETE CASCADE,
      sender_id INT NOT NULL REFERENCES ${USERS_TABLE}(id),
      content TEXT,
      image TEXT,
      audio TEXT,
      created_at TIMESTAMP DEFAULT NOW()
    );
  `);
  console.log("Channel_messages table tayyor");
}

async function initBlockedUsersTable() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS ${BLOCKED_USERS_TABLE} (
      id SERIAL PRIMARY KEY,
      blocker_id INT NOT NULL REFERENCES ${USERS_TABLE}(id) ON DELETE CASCADE,
      blocked_id INT NOT NULL REFERENCES ${USERS_TABLE}(id) ON DELETE CASCADE,
      created_at TIMESTAMP DEFAULT NOW(),
      UNIQUE(blocker_id, blocked_id)
    );
  `);
  console.log("Blocked_users table tayyor");
}

async function initSpamReportsTable() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS ${SPAM_REPORTS_TABLE} (
      id SERIAL PRIMARY KEY,
      reporter_id INT NOT NULL REFERENCES ${USERS_TABLE}(id) ON DELETE CASCADE,
      reported_id INT NOT NULL REFERENCES ${USERS_TABLE}(id) ON DELETE CASCADE,
      reason TEXT,
      created_at TIMESTAMP DEFAULT NOW()
    );
  `);
  console.log("Spam_reports table tayyor");
}

async function initFriendsTable() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS ${FRIENDS_TABLE} (
      id SERIAL PRIMARY KEY,
      sender_id INT NOT NULL REFERENCES ${USERS_TABLE}(id) ON DELETE CASCADE,
      receiver_id INT NOT NULL REFERENCES ${USERS_TABLE}(id) ON DELETE CASCADE,
      status VARCHAR(20) DEFAULT 'pending',
      created_at TIMESTAMP DEFAULT NOW(),
      UNIQUE(sender_id, receiver_id)
    );
  `);
  console.log("Friends table tayyor");
}

async function initPushSubscriptionsTable() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS push_subscriptions (
      id SERIAL PRIMARY KEY,
      user_id INT NOT NULL REFERENCES ${USERS_TABLE}(id) ON DELETE CASCADE,
      endpoint TEXT NOT NULL,
      p256dh TEXT NOT NULL,
      auth TEXT NOT NULL,
      created_at TIMESTAMP DEFAULT NOW(),
      UNIQUE(endpoint)
    );
  `);
  console.log("Push_subscriptions table tayyor");
}

// Foreign keys don't get indexes automatically in Postgres, and UNIQUE(a, b)
// only helps lookups on `a`. Everything below was a sequential scan.
async function initIndexes() {
  const indexes = [
    // Inbox: newest message per chat + the message list itself
    `CREATE INDEX IF NOT EXISTS idx_${MESSAGES_TABLE}_chat_created
       ON ${MESSAGES_TABLE} (chat_id, created_at DESC)`,
    // Inbox: unread badge. Partial predicate mirrors the query exactly.
    `CREATE INDEX IF NOT EXISTS idx_${MESSAGES_TABLE}_unread
       ON ${MESSAGES_TABLE} (chat_id, sender_id)
       WHERE COALESCE(is_read, FALSE) = FALSE`,
    // last_seen sync on boot
    `CREATE INDEX IF NOT EXISTS idx_${MESSAGES_TABLE}_sender_created
       ON ${MESSAGES_TABLE} (sender_id, created_at DESC)`,
    // UNIQUE(user1_id, user2_id) already covers user1_id
    `CREATE INDEX IF NOT EXISTS idx_${CHATS_TABLE}_user2
       ON ${CHATS_TABLE} (user2_id)`,

    `CREATE INDEX IF NOT EXISTS idx_${GROUP_MESSAGES_TABLE}_group_created
       ON ${GROUP_MESSAGES_TABLE} (group_id, created_at DESC)`,
    `CREATE INDEX IF NOT EXISTS idx_${CHANNEL_MESSAGES_TABLE}_channel_created
       ON ${CHANNEL_MESSAGES_TABLE} (channel_id, created_at DESC)`,

    // "which groups/channels am I in" — UNIQUE covers the other direction
    `CREATE INDEX IF NOT EXISTS idx_${GROUP_MEMBERS_TABLE}_user
       ON ${GROUP_MEMBERS_TABLE} (user_id)`,
    `CREATE INDEX IF NOT EXISTS idx_${CHANNEL_SUBSCRIBERS_TABLE}_user
       ON ${CHANNEL_SUBSCRIBERS_TABLE} (user_id)`,
    `CREATE INDEX IF NOT EXISTS idx_${FRIENDS_TABLE}_receiver
       ON ${FRIENDS_TABLE} (receiver_id)`,
    `CREATE INDEX IF NOT EXISTS idx_${BLOCKED_USERS_TABLE}_blocked
       ON ${BLOCKED_USERS_TABLE} (blocked_id)`,
    `CREATE INDEX IF NOT EXISTS idx_push_subscriptions_user
       ON push_subscriptions (user_id)`,
  ];

  for (const sql of indexes) {
    await pool.query(sql);
  }
  console.log(`Indexlar tayyor (${indexes.length} ta)`);
}

async function initDb() {
  await initUsersTable();
  await ensureAdminUser();
  await initChatsTable();
  await initMessagesTable();
  await initGroupsTable();
  await initGroupMembersTable();
  await initGroupMessagesTable();
  await initChannelsTable();
  await initChannelSubscribersTable();
  await initChannelMessagesTable();
  await initBlockedUsersTable();
  await initSpamReportsTable();
  await initFriendsTable();
  await initPushSubscriptionsTable();
  await initIndexes();

  // Sync last_seen with the user's most recent sent message if message is newer
  await pool.query(`
    UPDATE ${USERS_TABLE} u
    SET last_seen = sub.last_msg
    FROM (
      SELECT m.sender_id, MAX(m.created_at) AS last_msg
      FROM ${MESSAGES_TABLE} m
      GROUP BY m.sender_id
    ) sub
    WHERE u.id = sub.sender_id
      AND sub.last_msg IS NOT NULL
      AND (u.last_seen IS NULL OR sub.last_msg > u.last_seen)
  `);

  // Server qayta start bo'lganda barcha userlar offline — socket yo'q
  await pool.query(`UPDATE ${USERS_TABLE} SET is_online = FALSE`);

  console.log(`${new Date().toISOString()} Database ishga tushirildi`);
}

export { initDb };
