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
  await pool.query(`
    ALTER TABLE ${USERS_TABLE} ADD COLUMN IF NOT EXISTS bio VARCHAR(70);
  `);
  await pool.query(`
    ALTER TABLE ${USERS_TABLE} ADD COLUMN IF NOT EXISTS last_seen TIMESTAMP;
  `);
  console.log("Users table tayyor");
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

async function initDb() {
  await initUsersTable();
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
  console.log(`${new Date().toISOString()} Database ishga tushirildi`);
}

export { initDb };
