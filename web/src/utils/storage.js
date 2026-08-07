const KEYS = {
  USER: "app_user",
  AVATAR: "app_avatar",
  ROLE: "app_role",
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

const LOCAL_API_FALLBACK = "http://localhost:3003";

function trimTrailingSlashes(value = "") {
  return value.trim().replace(/\/+$/, "");
}

function isLocalHostname(hostname = "") {
  return hostname === "localhost" || hostname === "127.0.0.1";
}

function isLikelyLocalUrl(value = "") {
  return /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?(\/|$)/i.test(value);
}

function normalizeComparableHostname(hostname = "") {
  return String(hostname || "")
    .trim()
    .toLowerCase()
    .replace(/^www\./, "");
}

function shouldPreferCurrentOrigin(parsedUrl) {
  if (typeof window === "undefined") return false;

  const currentHostname = normalizeComparableHostname(window.location.hostname);
  const parsedHostname = normalizeComparableHostname(parsedUrl.hostname);

  if (!currentHostname || !parsedHostname) return false;
  if (currentHostname === parsedHostname) return true;

  return false;
}

function getCurrentOrigin() {
  if (typeof window === "undefined") return "";
  return trimTrailingSlashes(window.location.origin);
}

function getFallbackApiBaseUrl() {
  if (typeof window !== "undefined" && isLocalHostname(window.location.hostname)) {
    return LOCAL_API_FALLBACK;
  }

  return getCurrentOrigin() || LOCAL_API_FALLBACK;
}

function getDefaultApiBaseUrl() {
  const envBaseUrl = trimTrailingSlashes(
    import.meta.env.VITE_API_URL || import.meta.env.VITE_BASE_URL || "",
  );

  if (envBaseUrl) {
    return normalizeApiBaseUrl(envBaseUrl);
  }

  return getFallbackApiBaseUrl();
}

function getScopedStorageKey(baseKey, username = getUser()) {
  const normalizedUser = String(username || "").trim();
  if (!normalizedUser) return baseKey;
  return `bootchat:${normalizedUser}:${baseKey}`;
}

function normalizeApiBaseUrl(value) {
  const normalizedInput = trimTrailingSlashes(value || "");
  const fallback = getFallbackApiBaseUrl();

  if (!normalizedInput) {
    return normalizedInput || fallback;
  }

  if (
    isLikelyLocalUrl(normalizedInput) &&
    typeof window !== "undefined" &&
    !isLocalHostname(window.location.hostname)
  ) {
    return fallback;
  }

  if (normalizedInput.startsWith("/")) {
    return fallback;
  }

  try {
    const parsed = new URL(normalizedInput);

    if (parsed.origin === "null") {
      return fallback;
    }

    if (shouldPreferCurrentOrigin(parsed)) {
      return fallback;
    }

    if (!trimTrailingSlashes(parsed.pathname || "")) {
      return trimTrailingSlashes(parsed.origin);
    }

    return trimTrailingSlashes(parsed.origin);
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

export function getRole() {
  return localStorage.getItem(KEYS.ROLE) || "user";
}

export function setAuth(username, avatar, role = "user") {
  localStorage.setItem(KEYS.USER, username);
  if (avatar) localStorage.setItem(KEYS.AVATAR, avatar);
  else localStorage.removeItem(KEYS.AVATAR);
  localStorage.setItem(KEYS.ROLE, role || "user");
}

export function clearAuth() {
  localStorage.removeItem(KEYS.USER);
  localStorage.removeItem(KEYS.AVATAR);
  localStorage.removeItem(KEYS.ROLE);
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
    return JSON.parse(localStorage.getItem(getScopedStorageKey(KEYS.SAVED_MESSAGES)) || "[]");
  } catch {
    return [];
  }
}

export function saveMessage(msg) {
  const msgs = getSavedMessages();
  msgs.push({ ...msg, savedAt: Date.now() });
  localStorage.setItem(getScopedStorageKey(KEYS.SAVED_MESSAGES), JSON.stringify(msgs));
}

export function deleteSavedMessage(savedAt) {
  const msgs = getSavedMessages();
  const filtered = msgs.filter((m) => m.savedAt !== savedAt);
  localStorage.setItem(getScopedStorageKey(KEYS.SAVED_MESSAGES), JSON.stringify(filtered));
  return filtered;
}

export function clearSavedMessages() {
  localStorage.removeItem(getScopedStorageKey(KEYS.SAVED_MESSAGES));
}

export function getContacts() {
  try {
    return JSON.parse(localStorage.getItem(getScopedStorageKey(KEYS.CONTACTS)) || "[]");
  } catch {
    return [];
  }
}

export function saveContact(contact) {
  const contacts = getContacts();
  contacts.push(contact);
  localStorage.setItem(getScopedStorageKey(KEYS.CONTACTS), JSON.stringify(contacts));
}

export function getSyncedContacts() {
  try {
    return JSON.parse(localStorage.getItem(getScopedStorageKey(KEYS.SYNCED_CONTACTS)) || "[]");
  } catch {
    return [];
  }
}

export function saveSyncedContacts(contacts) {
  localStorage.setItem(getScopedStorageKey(KEYS.SYNCED_CONTACTS), JSON.stringify(contacts));
}

export function getProfileData() {
  return {
    fullName: localStorage.getItem(getScopedStorageKey("app_fullname")) || "",
    phone: localStorage.getItem(getScopedStorageKey(KEYS.PHONE)) || "",
    birthday: localStorage.getItem(getScopedStorageKey(KEYS.BIRTHDAY)) || "",
    bio: localStorage.getItem(getScopedStorageKey(KEYS.BIO)) || "",
    photos: JSON.parse(localStorage.getItem(getScopedStorageKey(KEYS.PHOTOS)) || "[]"),
  };
}

export function saveProfileData(data) {
  if (data.fullName !== undefined)
    localStorage.setItem(getScopedStorageKey("app_fullname"), data.fullName);
  if (data.phone !== undefined) localStorage.setItem(getScopedStorageKey(KEYS.PHONE), data.phone);
  if (data.birthday !== undefined)
    localStorage.setItem(getScopedStorageKey(KEYS.BIRTHDAY), data.birthday);
  if (data.bio !== undefined) localStorage.setItem(getScopedStorageKey(KEYS.BIO), data.bio);
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
  localStorage.setItem(
    key,
    typeof value === "string" ? value : JSON.stringify(value),
  );
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
    role: getRole(),
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
  else localStorage.removeItem(KEYS.AVATAR);
  localStorage.setItem(KEYS.ROLE, acc.role || "user");
  localStorage.setItem(getScopedStorageKey("app_fullname", acc.username), acc.fullName || acc.username);
  localStorage.setItem(getScopedStorageKey(KEYS.PHONE, acc.username), acc.phone || "");
  localStorage.setItem(getScopedStorageKey(KEYS.BIRTHDAY, acc.username), acc.birthday || "");
  localStorage.setItem(getScopedStorageKey(KEYS.BIO, acc.username), acc.bio || "");
  return acc;
}

export function removeAccount(username) {
  const accounts = getAccounts().filter((a) => a.username !== username);
  localStorage.setItem(ACCOUNTS_KEY, JSON.stringify(accounts));
  const scopedKeys = [
    getScopedStorageKey(KEYS.SAVED_MESSAGES, username),
    getScopedStorageKey(KEYS.CONTACTS, username),
    getScopedStorageKey(KEYS.SYNCED_CONTACTS, username),
    getScopedStorageKey("app_fullname", username),
    getScopedStorageKey(KEYS.PHONE, username),
    getScopedStorageKey(KEYS.BIRTHDAY, username),
    getScopedStorageKey(KEYS.BIO, username),
    getScopedStorageKey(KEYS.PHOTOS, username),
  ];
  scopedKeys.forEach((key) => localStorage.removeItem(key));
}

export { KEYS };
