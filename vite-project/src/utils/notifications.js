import { fetchJSON } from "@/utils/api";

const VAPID_PUBLIC_KEY = import.meta.env.VITE_VAPID_PUBLIC_KEY || "";

// Desktop notification (tab fokusda bo'lmaganda)
export function showDesktopNotification(title, body) {
  if (localStorage.getItem("app_desktop_notif") === "false") return;
  if (document.hasFocus()) return;
  if (!("Notification" in window)) return;

  if (Notification.permission === "granted") {
    new Notification(title, {
      body,
      icon: "/bootchat-logo.png",
      tag: "bootchat-" + title,
    });
  } else if (Notification.permission === "default") {
    Notification.requestPermission();
  }
}

// Service Worker registration
export async function registerServiceWorker() {
  if (!("serviceWorker" in navigator)) return null;
  try {
    const registration = await navigator.serviceWorker.register(
      `${import.meta.env.BASE_URL}sw.js`,
      { updateViaCache: "none" },
    );
    registration.update().catch(() => {});
    return registration;
  } catch (err) {
    console.warn("Service Worker registration failed:", err);
    return null;
  }
}

// VAPID key base64url -> Uint8Array
function urlBase64ToUint8Array(base64String) {
  const padding = "=".repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/");
  const rawData = atob(base64);
  const outputArray = new Uint8Array(rawData.length);
  for (let i = 0; i < rawData.length; i++) {
    outputArray[i] = rawData.charCodeAt(i);
  }
  return outputArray;
}

// Push notification ga subscribe bo'lish
export async function subscribeToPush(username) {
  if (!VAPID_PUBLIC_KEY || !("serviceWorker" in navigator) || !("PushManager" in window)) return;
  if (Notification.permission === "denied") {
    return;
  }

  try {
    const registration = await navigator.serviceWorker.ready;
    const existingSub = await registration.pushManager.getSubscription();

    if (existingSub) {
      // Mavjud subscription ni backendga yuborish (brauzer o'zgargan bo'lishi mumkin)
      await sendSubscriptionToServer(existingSub, username);
      return;
    }

    const subscription = await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(VAPID_PUBLIC_KEY),
    });

    await sendSubscriptionToServer(subscription, username);
  } catch (err) {
    console.warn("Push subscription failed:", err);
  }
}

async function sendSubscriptionToServer(subscription, username) {
  try {
    await fetchJSON("/api/push/subscribe", {
      method: "POST",
      body: JSON.stringify({ subscription, username }),
    });
  } catch (err) {
    console.warn("Push subscribe server error:", err);
  }
}
