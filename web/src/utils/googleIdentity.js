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

  win[GOOGLE_INIT_KEY] = null;

  gsi.initialize({
    client_id: clientId,
    callback: (response) => {
      win[GOOGLE_HANDLER_KEY]?.(response);
    },
    auto_select: false,
    use_fedcm_for_prompt: false, // custom button bilan FedCM ishlamaydi
  });

  gsi.disableAutoSelect?.();
  win[GOOGLE_INIT_KEY] = clientId;

  return true;
}

// ✅ container elementga Google tugmasini render qiladi, ichki elementni qaytaradi
export function renderGoogleButton(container, isDark = false) {
  const win = getWindowObject();
  if (!win || !container) return null;

  const gsi = win.google?.accounts?.id;
  if (!gsi) return null;

  container.innerHTML = "";

  gsi.renderButton(container, {
    type: "standard",
    theme: isDark ? "filled_black" : "outline",
    size: "large",
    text: "signin_with",
    shape: "pill",
    logo_alignment: "left",
    width: container.offsetWidth || 320,
  });

  return container.querySelector("div[role=button], button");
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