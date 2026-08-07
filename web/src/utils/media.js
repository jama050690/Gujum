import { getBaseUrl } from "@/utils/api";

function trimTrailingSlashes(value = "") {
  return value.replace(/\/+$/, "");
}

function joinUrl(base, path) {
  const safeBase = trimTrailingSlashes(base || "");
  const safePath = path.startsWith("/") ? path : `/${path}`;
  if (!safeBase) return safePath;
  return `${safeBase}${safePath}`;
}

export function resolveMediaUrl(path, base = getBaseUrl()) {
  if (!path || typeof path !== "string") return "";
  const trimmed = path.trim();
  if (!trimmed) return "";
  if (/^(data:|blob:|https?:\/\/)/i.test(trimmed)) return trimmed;

  const normalizedPath = trimmed.replace(/\\/g, "/");
  const normalizedBase = trimTrailingSlashes(base || "");

  if (!normalizedBase) {
    if (typeof window !== "undefined" && window.location?.origin) {
      return joinUrl(window.location.origin, normalizedPath);
    }
    return normalizedPath;
  }

  return joinUrl(normalizedBase, normalizedPath);
}
