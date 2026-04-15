import "./env.js";
import { Pool } from "pg";

const host = typeof process.env.DB_HOST === "string" ? process.env.DB_HOST.trim() : "";
const user = typeof process.env.DB_USER === "string" ? process.env.DB_USER.trim() : "";
const password = typeof process.env.DB_PASSWORD === "string" ? process.env.DB_PASSWORD.trim() : "";
const database = typeof process.env.DB_NAME === "string" ? process.env.DB_NAME.trim() : "";

const pool = new Pool({
  host,
  port: Number(process.env.DB_PORT || 5432),
  user,
  password,
  database,
});

const USERS_TABLE = "users";
const MESSAGES_TABLE = "messages";
const CHATS_TABLE = "chat_messages";
const GROUPS_TABLE = "groups";
const GROUP_MEMBERS_TABLE = "group_members";
const GROUP_MESSAGES_TABLE = "group_messages";
const CHANNELS_TABLE = "channels";
const CHANNEL_SUBSCRIBERS_TABLE = "channel_subscribers";
const CHANNEL_MESSAGES_TABLE = "channel_messages";
const BLOCKED_USERS_TABLE = "blocked_users";
const SPAM_REPORTS_TABLE = "spam_reports";
const FRIENDS_TABLE = "friends";

export {
  pool,
  USERS_TABLE,
  MESSAGES_TABLE,
  CHATS_TABLE,
  GROUPS_TABLE,
  GROUP_MEMBERS_TABLE,
  GROUP_MESSAGES_TABLE,
  CHANNELS_TABLE,
  CHANNEL_SUBSCRIBERS_TABLE,
  CHANNEL_MESSAGES_TABLE,
  BLOCKED_USERS_TABLE,
  SPAM_REPORTS_TABLE,
  FRIENDS_TABLE,
};
