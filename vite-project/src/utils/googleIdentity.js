const GOOGLE_SCRIPT_ID = "google-identity-service";
const GOOGLE_HANDLER_KEY = "__bootchatGoogleCredentialHandler";
const GOOGLE_INIT_KEY = "__bootchatGoogleIdentityClientId";
let googleScriptPromise = null;

function getWindowObject() {
  if (typeof window === "undefined") return null;
  return window;
}

export function setGoogleCredentialHandler(handler) {
  const win = getWindowObject();
  if (!win) return;
  win[GOOGLE_HANDLER_KEY] = handler || null;
}

export function initializeGoogleIdentity(clientId) {
  const win = getWindowObject();
  if (!win || !clientId) return false;

  const gsi = win.google?.accounts?.id;
  if (!gsi) return false;

  if (win[GOOGLE_INIT_KEY] !== clientId) {
    gsi.initialize({
      client_id: clientId,
      callback: (response) => {
        win[GOOGLE_HANDLER_KEY]?.(response);
      },
      auto_select: false,
      use_fedcm_for_prompt: true, // ✅ FedCM yoqildi — postMessage xatosini hal qiladi
    });
    gsi.disableAutoSelect?.();
    win[GOOGLE_INIT_KEY] = clientId;
  }

  return true;
}

// ✅ Yangi funksiya — custom button bilan ishlash uchun
export function triggerGoogleSignIn() {
  const win = getWindowObject();
  if (!win) return;

  const gsi = win.google?.accounts?.id;
  if (!gsi) return;

  gsi.prompt((notification) => {
    // Prompt yopilsa yoki blok bo'lsa — callback orqali hal qilinadi
    if (notification.isNotDisplayed() || notification.isSkippedMoment()) {
      console.warn("Google prompt ko'rsatilmadi:", notification.getNotDisplayedReason?.() || notification.getSkippedReason?.());
    }
  });
}

export function loadGoogleIdentityScript() {
  const win = getWindowObject();
  if (!win) return Promise.resolve(false);

  if (win.google?.accounts?.id) {
    return Promise.resolve(true);
  }

  if (googleScriptPromise) {
    return googleScriptPromise;
  }

  googleScriptPromise = new Promise((resolve, reject) => {
    let script = document.getElementById(GOOGLE_SCRIPT_ID);

    const handleLoad = () => resolve(true);
    const handleError = () => {
      googleScriptPromise = null;
      reject(new Error("Google Identity script yuklanmadi"));
    };

    if (!script) {
      script = document.createElement("script");
      script.id = GOOGLE_SCRIPT_ID;
      script.src = "https://accounts.google.com/gsi/client";
      script.async = true;
      script.defer = true;
      script.addEventListener("error", handleError, { once: true });
      script.addEventListener("load", handleLoad, { once: true });
      document.head.appendChild(script);
      return;
    }

    if (win.google?.accounts?.id) {
      resolve(true);
      return;
    }

    script.addEventListener("error", handleError, { once: true });
    script.addEventListener("load", handleLoad, { once: true });
  });

  return googleScriptPromise;
}