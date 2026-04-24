import { useEffect, useState } from "react";

const mediaAvailabilityCache = new Map();

function isSkippableUrl(src) {
  return /^(data:|blob:)/i.test(src);
}

export function markMediaUnavailable(src) {
  if (!src) return;
  mediaAvailabilityCache.set(src, "missing");
}

export function useMediaAvailability(src) {
  const [status, setStatus] = useState(() => {
    if (!src) return "idle";
    if (isSkippableUrl(src)) return "available";
    return mediaAvailabilityCache.get(src) || "available";
  });

  useEffect(() => {
    if (!src) {
      setStatus("idle");
      return undefined;
    }

    if (isSkippableUrl(src)) {
      setStatus("available");
      return undefined;
    }

    const cachedStatus = mediaAvailabilityCache.get(src);
    setStatus(cachedStatus || "available");
    return undefined;
  }, [src]);

  return {
    status,
    isAvailable: status === "available",
    isMissing: status === "missing",
    isChecking: status === "checking",
  };
}
