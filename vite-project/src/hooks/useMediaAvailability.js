import { useEffect, useState } from "react";

const mediaAvailabilityCache = new Map();

function isSkippableUrl(src) {
  return /^(data:|blob:)/i.test(src);
}

function canProbeMedia(src) {
  if (!src || typeof window === "undefined" || isSkippableUrl(src)) {
    return false;
  }

  try {
    const url = new URL(src, window.location.origin);
    return url.origin === window.location.origin && /\/uploads\//i.test(url.pathname);
  } catch {
    return false;
  }
}

async function probeMedia(src, signal) {
  const response = await fetch(src, {
    method: "HEAD",
    signal,
    cache: "no-store",
  });

  if (!response.ok) {
    return "missing";
  }

  const contentLength = response.headers.get("content-length");
  if (contentLength !== null && Number(contentLength) <= 0) {
    return "missing";
  }

  return "available";
}

export function markMediaUnavailable(src) {
  if (!src) return;
  mediaAvailabilityCache.set(src, "missing");
}

export function useMediaAvailability(src) {
  const [status, setStatus] = useState(() => {
    if (!src) return "idle";
    if (!canProbeMedia(src)) return "available";
    return mediaAvailabilityCache.get(src) || "checking";
  });

  useEffect(() => {
    if (!src) {
      setStatus("idle");
      return undefined;
    }

    if (!canProbeMedia(src)) {
      setStatus("available");
      return undefined;
    }

    const cachedStatus = mediaAvailabilityCache.get(src);
    if (cachedStatus) {
      setStatus(cachedStatus);
      return undefined;
    }

    const controller = new AbortController();
    let isActive = true;
    setStatus("checking");

    probeMedia(src, controller.signal)
      .then((nextStatus) => {
        mediaAvailabilityCache.set(src, nextStatus);
        if (isActive) {
          setStatus(nextStatus);
        }
      })
      .catch((error) => {
        if (controller.signal.aborted || error?.name === "AbortError") {
          return;
        }

        mediaAvailabilityCache.set(src, "missing");
        if (isActive) {
          setStatus("missing");
        }
      });

    return () => {
      isActive = false;
      controller.abort();
    };
  }, [src]);

  return {
    status,
    isAvailable: status === "available",
    isMissing: status === "missing",
    isChecking: status === "checking",
  };
}
