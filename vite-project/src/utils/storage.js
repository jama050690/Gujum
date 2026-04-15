const KEYS = {
  USER: "app_user",
  AVATAR: "app_avatar",
  MODE: "mode",
  API_BASE_URL: "app_api_base_url",
  SAVED_MESSAGES: "saved_messages",
  CONTACTS: "app_contacts",
  SYNCED_CONTACTS: "app_synced_contacts",
  PHONE: "app_phone",
  BIRTHDAY: "app_birthday",
  BIO: "app_bio",
  PHOTOS: "app_photos",
  LANGUAGE: "app_language",
  MESSAGE_SIZE: "app_message_size",
  SEND_BY_ENTER: "app_send_by_enter",
  CHAT_BG: "app_chat_bg",
};

const LOCAL_API_FALLBACK = "http://localhost:4000";
const PRODUCTION_API_PREFIX = "/api/bootchat";

function trimTrailingSlashes(value = "") {
  return value.trim().replace(/\/+$/, "");
}

function isLocalHostname(hostname = "") {
  return hostname === "localhost" || hostname === "127.0.0.1";
}

function isLikelyLocalUrl(value = "") {
  return /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?(\/|$)/i.test(value);
}

function getDefaultApiBaseUrl() {
  const envBaseUrl = trimTrailingSlashes(import.meta.env.VITE_BASE_URL || "");

  if (typeof window === "undefined") {
    return envBaseUrl || LOCAL_API_FALLBACK;
  }

  const currentOrigin = trimTrailingSlashes(window.location.origin);

  if (isLocalHostname(window.location.hostname)) {
    if (envBaseUrl.startsWith("/")) {
      return `${currentOrigin}${envBaseUrl}`;
    }
    return envBaseUrl || LOCAL_API_FALLBACK;
  }

  if (envBaseUrl) {
    if (envBaseUrl.startsWith("/")) {
      return `${currentOrigin}${envBaseUrl}`;
    }
    if (!isLikelyLocalUrl(envBaseUrl)) {
      return envBaseUrl;
    }
  }

  return `${currentOrigin}${PRODUCTION_API_PREFIX}`;
}

function normalizeApiBaseUrl(value) {
  const fallback = getDefaultApiBaseUrl();
  const normalizedInput = trimTrailingSlashes(value || "");

  if (!normalizedInput || typeof window === "undefined") {
    return normalizedInput || fallback;
  }

  const currentOrigin = trimTrailingSlashes(window.location.origin);
  const productionBaseUrl = `${currentOrigin}${PRODUCTION_API_PREFIX}`;

  if (isLikelyLocalUrl(normalizedInput) && !isLocalHostname(window.location.hostname)) {
    return productionBaseUrl;
  }

  let normalized = normalizedInput;
  if (normalized.startsWith("/")) {
    normalized = `${currentOrigin}${normalized}`;
  }

  try {
    const parsed = new URL(normalized);

    if (parsed.origin === currentOrigin) {
      const path = trimTrailingSlashes(parsed.pathname || "");
      if (
        !path ||
        path === "/bootchat" ||
        path.startsWith("/bootchat/") ||
        !path.startsWith(PRODUCTION_API_PREFIX)
      ) {
        return productionBaseUrl;
      }
    }

    return trimTrailingSlashes(parsed.toString());
  } catch {
    return fallback;
  }
}

export function getUser() {
  return localStorage.getItem(KEYS.USER);
}

export function getAvatar() {
  return localStorage.getItem(KEYS.AVATAR);
}

export function setAuth(username, avatar) {
  localStorage.setItem(KEYS.USER, username);
  if (avatar) localStorage.setItem(KEYS.AVATAR, avatar);
}

export function clearAuth() {
  localStorage.removeItem(KEYS.USER);
  localStorage.removeItem(KEYS.AVATAR);
}

export function isDarkMode() {
  return localStorage.getItem(KEYS.MODE) === "dark_mode";
}

export function setDarkMode(dark) {
  localStorage.setItem(KEYS.MODE, dark ? "dark_mode" : "light_mode");
}

export function getApiBaseUrl() {
  const saved = localStorage.getItem(KEYS.API_BASE_URL);
  const normalized = normalizeApiBaseUrl(saved);

  if (normalized !== trimTrailingSlashes(saved || "")) {
    localStorage.setItem(KEYS.API_BASE_URL, normalized);
  }

  return normalized;
}

export function saveApiBaseUrl(url) {
  localStorage.setItem(KEYS.API_BASE_URL, normalizeApiBaseUrl(url));
}

export function getSavedMessages() {
  try {
    return JSON.parse(localStorage.getItem(KEYS.SAVED_MESSAGES) || "[]");
  } catch {
    return [];
  }
}

export function saveMessage(msg) {
  const msgs = getSavedMessages();
  msgs.push({ ...msg, savedAt: Date.now() });
  localStorage.setItem(KEYS.SAVED_MESSAGES, JSON.stringify(msgs));
}

export function deleteSavedMessage(savedAt) {
  const msgs = getSavedMessages();
  const filtered = msgs.filter((m) => m.savedAt !== savedAt);
  localStorage.setItem(KEYS.SAVED_MESSAGES, JSON.stringify(filtered));
  return filtered;
}

export function clearSavedMessages() {
  localStorage.removeItem(KEYS.SAVED_MESSAGES);
}

export function getContacts() {
  try {
    return JSON.parse(localStorage.getItem(KEYS.CONTACTS) || "[]");
  } catch {
    return [];
  }
}

export function saveContact(contact) {
  const contacts = getContacts();
  contacts.push(contact);
  localStorage.setItem(KEYS.CONTACTS, JSON.stringify(contacts));
}

export function getSyncedContacts() {
  try {
    return JSON.parse(localStorage.getItem(KEYS.SYNCED_CONTACTS) || "[]");
  } catch {
    return [];
  }
}

export function saveSyncedContacts(contacts) {
  localStorage.setItem(KEYS.SYNCED_CONTACTS, JSON.stringify(contacts));
}

export function getProfileData() {
  return {
    fullName: localStorage.getItem("app_fullname") || "",
    phone: localStorage.getItem(KEYS.PHONE) || "",
    birthday: localStorage.getItem(KEYS.BIRTHDAY) || "",
    bio: localStorage.getItem(KEYS.BIO) || "",
    photos: JSON.parse(localStorage.getItem(KEYS.PHOTOS) || "[]"),
  };
}

export function saveProfileData(data) {
  if (data.fullName !== undefined) localStorage.setItem("app_fullname", data.fullName);
  if (data.phone !== undefined) localStorage.setItem(KEYS.PHONE, data.phone);
  if (data.birthday !== undefined) localStorage.setItem(KEYS.BIRTHDAY, data.birthday);
  if (data.bio !== undefined) localStorage.setItem(KEYS.BIO, data.bio);
}

export function getSettings() {
  return {
    language: localStorage.getItem(KEYS.LANGUAGE) || "English",
    messageSize: parseInt(localStorage.getItem(KEYS.MESSAGE_SIZE) || "16"),
    sendByEnter: localStorage.getItem(KEYS.SEND_BY_ENTER) !== "false",
    chatBg: localStorage.getItem(KEYS.CHAT_BG) || "",
  };
}

export function saveSetting(key, value) {
  localStorage.setItem(key, typeof value === "string" ? value : JSON.stringify(value));
}

// ─── Multi-account ───

const ACCOUNTS_KEY = "app_accounts";

export function getAccounts() {
  try {
    return JSON.parse(localStorage.getItem(ACCOUNTS_KEY) || "[]");
  } catch {
    return [];
  }
}

export function saveAccountSnapshot() {
  const username = getUser();
  if (!username) return;
  const accounts = getAccounts();
  const profile = getProfileData();
  const snapshot = {
    username,
    avatar: getAvatar(),
    fullName: profile.fullName || username,
    phone: profile.phone,
    birthday: profile.birthday,
    bio: profile.bio,
  };
  const idx = accounts.findIndex((a) => a.username === username);
  if (idx >= 0) accounts[idx] = snapshot;
  else accounts.push(snapshot);
  localStorage.setItem(ACCOUNTS_KEY, JSON.stringify(accounts));
}

export function restoreAccount(username) {
  const accounts = getAccounts();
  const acc = accounts.find((a) => a.username === username);
  if (!acc) return null;
  localStorage.setItem(KEYS.USER, acc.username);
  if (acc.avatar) localStorage.setItem(KEYS.AVATAR, acc.avatar);
  localStorage.setItem("app_fullname", acc.fullName || acc.username);
  localStorage.setItem(KEYS.PHONE, acc.phone || "");
  localStorage.setItem(KEYS.BIRTHDAY, acc.birthday || "");
  localStorage.setItem(KEYS.BIO, acc.bio || "");
  return acc;
}

export function removeAccount(username) {
  const accounts = getAccounts().filter((a) => a.username !== username);
  localStorage.setItem(ACCOUNTS_KEY, JSON.stringify(accounts));
}

export { KEYS };
