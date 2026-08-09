import {
  pool,
  USERS_TABLE,
  CHATS_TABLE,
  MESSAGES_TABLE,
  BLOCKED_USERS_TABLE,
  FRIENDS_TABLE,
  MIGRATIONS_TABLE,
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
  // Idempotentlik kaliti: klient har bir xabar uchun bir marta ID yaratadi va
  // qayta yuborishda (uzilib qolgan socket, retry, ikki marta bosilgan tugma)
  // o'shani jo'natadi. Telegram'dagi random_id bilan bir xil g'oya.
  await pool.query(`
    ALTER TABLE ${MESSAGES_TABLE} ADD COLUMN IF NOT EXISTS client_msg_id TEXT;
  `);
  await pool.query(`
    CREATE UNIQUE INDEX IF NOT EXISTS ${MESSAGES_TABLE}_client_msg_uniq
    ON ${MESSAGES_TABLE} (sender_id, client_msg_id)
    WHERE client_msg_id IS NOT NULL;
  `);
  console.log("Messages table tayyor");
}

/// "Faqat men uchun o'chirish" — xabar bazada qoladi, lekin shu foydalanuvchiga
/// ko'rsatilmaydi. "Hamma uchun" o'chirishda qator butunlay yo'q qilinadi.
async function initMessageDeletionsTable() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS message_deletions (
      message_id INT NOT NULL REFERENCES ${MESSAGES_TABLE}(id) ON DELETE CASCADE,
      user_id INT NOT NULL REFERENCES ${USERS_TABLE}(id) ON DELETE CASCADE,
      deleted_at TIMESTAMPTZ DEFAULT NOW(),
      PRIMARY KEY (message_id, user_id)
    );
  `);
  await pool.query(`
    CREATE INDEX IF NOT EXISTS message_deletions_user_idx
    ON message_deletions (user_id);
  `);
  console.log("Message_deletions table tayyor");
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

    `CREATE INDEX IF NOT EXISTS idx_${FRIENDS_TABLE}_receiver
       ON ${FRIENDS_TABLE} (receiver_id)`,
    `CREATE INDEX IF NOT EXISTS idx_${BLOCKED_USERS_TABLE}_blocked
       ON ${BLOCKED_USERS_TABLE} (blocked_id)`,
    `CREATE INDEX IF NOT EXISTS idx_push_subscriptions_user
       ON push_subscriptions (user_id)`,

    // TTL tozalash butun jadval bo'ylab created_at bo'yicha o'chiradi.
    // idx_..._chat_created chat_id dan boshlanadi, shuning uchun bu so'rovga
    // yaramaydi — usiz har safar to'liq skan bo'lardi.
    `CREATE INDEX IF NOT EXISTS idx_${MESSAGES_TABLE}_created
       ON ${MESSAGES_TABLE} (created_at)`,

    // Kontaktlarni moslashtirish raqamning oxirgi 9 raqami bo'yicha qidiradi.
    // Ifoda ustun emas, shuning uchun oddiy indeks yaramaydi — usiz har bir
    // so'rovda butun users jadvali skanerlanib, har qatorga regexp qo'llanardi.
    `CREATE INDEX IF NOT EXISTS idx_${USERS_TABLE}_phone_tail
       ON ${USERS_TABLE} (RIGHT(REGEXP_REPLACE(phone, '\\D', '', 'g'), 9))
       WHERE phone IS NOT NULL`,

    // Qo'ng'iroqlar tarixi xabarlar jadvalidan "__CALL:%__" naqshi bo'yicha
    // olinadi. Naqsh indekslanmaydi, shuning uchun so'rov foydalanuvchining
    // barcha suhbatlaridagi HAMMA xabarni ko'zdan kechirardi va yozishmalar
    // o'sgani sari sekinlashardi. Qisman indeks faqat qo'ng'iroq
    // yozuvlarini, vaqt bo'yicha tartiblangan holda saqlaydi — so'rovdagi
    // shart bilan aynan bir xil, aks holda rejalashtiruvchi undan
    // foydalana olmaydi.
    `CREATE INDEX IF NOT EXISTS idx_${MESSAGES_TABLE}_call_logs
       ON ${MESSAGES_TABLE} (created_at DESC)
       WHERE content LIKE '__CALL:%__'`,

    // O'chirilgan akkauntlar arxivi 2 yildan keyin shu ustun bo'yicha
    // tozalanadi.
    `CREATE INDEX IF NOT EXISTS idx_deleted_accounts_deleted_at
       ON deleted_accounts (deleted_at)`,
  ];

  for (const sql of indexes) {
    await pool.query(sql);
  }
  console.log(`Indexlar tayyor (${indexes.length} ta)`);
}

/// Bir marta bajariladigan migratsiyalar ro'yxati.
///
/// Har bir migratsiya bajarilgach ${MIGRATIONS_TABLE} ga yoziladi va
/// keyingi ishga tushishlarda o'tkazib yuboriladi. Aks holda jadval
/// tashlash kabi buyruqlar server har qayta ishga tushganda qaytadan
/// bajarilaverardi.
const MIGRATIONS = [
  {
    id: "2026_08_drop_groups_and_channels",
    // Guruh va kanallar ilovadan butunlay chiqarildi. Jadvallari qolsa,
    // faqat joy egallaydi va zaxira nusxalarni kattalashtiradi. Bog'liq
    // jadvallar CASCADE bilan birga ketadi.
    statements: [
      "DROP TABLE IF EXISTS group_messages CASCADE",
      "DROP TABLE IF EXISTS group_members CASCADE",
      "DROP TABLE IF EXISTS groups CASCADE",
      "DROP TABLE IF EXISTS channel_messages CASCADE",
      "DROP TABLE IF EXISTS channel_subscribers CASCADE",
      "DROP TABLE IF EXISTS channels CASCADE",
    ],
  },
  {
    id: "2026_08_drop_spam_reports",
    // Spam haqida xabar berish ilovadan olib tashlandi.
    statements: ["DROP TABLE IF EXISTS spam_reports CASCADE"],
  },
];

async function runMigrations() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS ${MIGRATIONS_TABLE} (
      id VARCHAR(120) PRIMARY KEY,
      applied_at TIMESTAMP NOT NULL DEFAULT NOW()
    );
  `);

  for (const migration of MIGRATIONS) {
    const { rows } = await pool.query(
      `SELECT 1 FROM ${MIGRATIONS_TABLE} WHERE id = $1`,
      [migration.id]
    );
    if (rows.length > 0) continue;

    const client = await pool.connect();
    try {
      await client.query("BEGIN");
      for (const sql of migration.statements) {
        await client.query(sql);
      }
      await client.query(`INSERT INTO ${MIGRATIONS_TABLE} (id) VALUES ($1)`, [
        migration.id,
      ]);
      await client.query("COMMIT");
      console.log(`Migratsiya bajarildi: ${migration.id}`);
    } catch (e) {
      await client.query("ROLLBACK");
      // Migratsiya o'tmasa server baribir ko'tarilishi kerak — keyingi
      // ishga tushishda qayta urinadi.
      console.error(`Migratsiya xatosi (${migration.id}): ${e.message}`);
    } finally {
      client.release();
    }
  }
}

async function initDb() {
  await runMigrations();
  await initUsersTable();
  await ensureAdminUser();
  await initChatsTable();
  await initMessagesTable();
  await initMessageDeletionsTable();
  await initBlockedUsersTable();
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
