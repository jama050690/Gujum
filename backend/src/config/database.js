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
const BLOCKED_USERS_TABLE = "blocked_users";
const FRIENDS_TABLE = "friends";
// Bir marta bajarilgan migratsiyalar yozib boriladigan jadval.
const MIGRATIONS_TABLE = "schema_migrations";

export {
  pool,
  USERS_TABLE,
  MESSAGES_TABLE,
  CHATS_TABLE,
  BLOCKED_USERS_TABLE,
  FRIENDS_TABLE,
  MIGRATIONS_TABLE,
};
