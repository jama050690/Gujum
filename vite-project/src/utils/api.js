import { getApiBaseUrl } from "@/utils/storage";

const BASE_URL = getApiBaseUrl();

export function getBaseUrl() {
  return getApiBaseUrl();
}

export async function fetchJSON(url, options = {}) {
  const res = await fetch(`${getBaseUrl()}${url}`, {
    credentials: "include",
    headers: { "Content-Type": "application/json", ...options.headers },
    ...options,
  });
  if (res.status === 401) {
    localStorage.removeItem("app_user");
    localStorage.removeItem("app_avatar");
    window.location.href = import.meta.env.VITE_BASE_PATH || "/";
    throw new Error("Sessiya tugadi, qayta kiring");
  }
  if (!res.ok) {
    const err = await res.json().catch(() => ({ message: res.statusText }));
    throw new Error(err.message || "Request failed");
  }
  return res.json();
}

export async function uploadFile(url, formData) {
  const res = await fetch(`${getBaseUrl()}${url}`, {
    method: "POST",
    credentials: "include",
    body: formData,
  });
  if (!res.ok) throw new Error("Upload failed");
  return res.json();
}

export { BASE_URL };
