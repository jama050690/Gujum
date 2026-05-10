import { forwardRef, useCallback, useEffect, useRef, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { useAuth } from "@/context/AuthContext";
import { useLanguage } from "@/context/LanguageContext";
import { useTheme } from "@/context/ThemeContext";
import { getBaseUrl } from "@/utils/api";
import { BRAND_LOGO_URL } from "@/utils/branding";
import { saveProfileData } from "@/utils/storage";
import {
  initializeGoogleIdentity,
  loadGoogleIdentityScript,
  setGoogleCredentialHandler,
  triggerGoogleSignIn, // ✅ yangi funksiya
} from "@/utils/googleIdentity";

const LAST_LOGIN_USERNAME_KEY = "bootchat:last_login_username";
const REQUEST_TIMEOUT_MS = 10000;
const LANGUAGE_OPTIONS = [
  { value: "uz", label: "UZ" },
  { value: "en", label: "EN" },
  { value: "ru", label: "RU" },
];

export default function LoginPage() {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [profilePreview, setProfilePreview] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const [googleLoading, setGoogleLoading] = useState(false);
  const [googleReady, setGoogleReady] = useState(false);
  const [savedUsername, setSavedUsername] = useState("");
  const [inputsUnlocked, setInputsUnlocked] = useState(false);
  const usernameInputRef = useRef(null);
  const passwordInputRef = useRef(null);
  const profileInputRef = useRef(null);
  const formRootRef = useRef(null);
  const userInteractedRef = useRef(false);
  const navigate = useNavigate();
  const { login } = useAuth();
  const { isDark } = useTheme();
  const { t, lang, changeLanguage } = useLanguage();
  const GOOGLE_CLIENT_ID = import.meta.env.VITE_GOOGLE_CLIENT_ID || "";

  const tr = useCallback(
    (key, fallback) => {
      const value = t(key);
      return value === key ? fallback : value;
    },
    [t],
  );

  const withTimeout = useCallback(async (url, options = {}) => {
    const controller = new AbortController();
    const timeoutId = window.setTimeout(
      () => controller.abort(),
      REQUEST_TIMEOUT_MS,
    );
    try {
      return await fetch(url, { ...options, signal: controller.signal });
    } finally {
      window.clearTimeout(timeoutId);
    }
  }, []);

  const getRequestErrorMessage = useCallback(
    (err, fallbackMessage) => {
      const apiBaseUrl = getBaseUrl();
      if (err?.name === "AbortError") {
        return `${tr("login_timeout", "Server javobi kechikyapti.")}\nAPI: ${apiBaseUrl}`;
      }
      if (err instanceof TypeError && /fetch/i.test(err.message || "")) {
        return `${tr("login_network_failed", "Serverga ulanib bo'lmadi.")}\nAPI: ${apiBaseUrl}`;
      }
      return err?.message || fallbackMessage;
    },
    [tr],
  );

  const completeLogin = useCallback(
    (userData) => {
      sessionStorage.removeItem("switch_to_user");
      localStorage.setItem(LAST_LOGIN_USERNAME_KEY, userData.username);
      saveProfileData({
        fullName: userData.fullName || userData.username,
        phone: userData.phone || "",
        birthday: userData.birthday || "",
        bio: userData.bio || "",
      });
      login(userData.username, userData.avatar, userData.fullName, userData.role);
      navigate(userData.role === "admin" ? `/${lang}/admin` : `/${lang}`);
    },
    [lang, login, navigate],
  );

  const handleGoogleCredential = useCallback(
    async (response) => {
      setError("");
      setGoogleLoading(true);
      try {
        const credential = response?.credential;
        if (!credential) {
          throw new Error(tr("login_google_failed", "Google orqali kirishda xatolik."));
        }

        const res = await withTimeout(`${getBaseUrl()}/api/login/google`, {
          method: "POST",
          credentials: "include",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ credential }),
        });

        const data = await res.json().catch(() => ({}));

        if (!res.ok) {
          if (res.status === 404) {
            throw new Error(
              tr("login_google_backend_missing", "Google login backend hali sozlanmagan."),
            );
          }
          throw new Error(
            data.message || tr("login_google_failed", "Google orqali kirishda xatolik."),
          );
        }

        if (!data?.user?.username) {
          throw new Error(
            tr("login_google_bad_response", "Google login javobi noto'g'ri formatda."),
          );
        }

        completeLogin(data.user);
      } catch (err) {
        setError(
          getRequestErrorMessage(err, tr("login_google_failed", "Google orqali kirishda xatolik.")),
        );
      } finally {
        setGoogleLoading(false);
      }
    },
    [completeLogin, getRequestErrorMessage, tr, withTimeout],
  );

  useEffect(() => {
    const rememberedUsername =
      sessionStorage.getItem("switch_to_user") ||
      localStorage.getItem(LAST_LOGIN_USERNAME_KEY) ||
      "";
    setSavedUsername(rememberedUsername.trim());
  }, []);

  const clearVisibleAutofill = useCallback(() => {
    if (userInteractedRef.current) return;
    setUsername("");
    setPassword("");
    formRootRef.current?.querySelectorAll("input").forEach((input) => {
      input.value = "";
      input.blur?.();
    });
    if (document.activeElement instanceof HTMLElement) {
      document.activeElement.blur();
    }
  }, []);

  useEffect(() => {
    const timers = [0, 150, 500].map((delay) =>
      window.setTimeout(clearVisibleAutofill, delay),
    );
    return () => {
      timers.forEach((timerId) => window.clearTimeout(timerId));
    };
  }, [clearVisibleAutofill]);

  // ✅ googleButtonRef va renderButton olib tashlandi — faqat initialize qilinadi
  useEffect(() => {
    setGoogleReady(false);
    if (!GOOGLE_CLIENT_ID) return;

    let cancelled = false;
    setGoogleCredentialHandler(handleGoogleCredential);

    loadGoogleIdentityScript()
      .then(() => {
        if (cancelled) return;
        if (initializeGoogleIdentity(GOOGLE_CLIENT_ID)) {
          setGoogleReady(true);
        }
      })
      .catch(() => {
        if (!cancelled) setGoogleReady(false);
      });

    return () => {
      cancelled = true;
      setGoogleCredentialHandler(null);
    };
  }, [GOOGLE_CLIENT_ID, handleGoogleCredential]);

  // ✅ Endi triggerGoogleSignIn() ishlatiladi — yashirin div kerak emas
  const handleGoogleLoginClick = () => {
    setError("");

    if (!GOOGLE_CLIENT_ID) {
      setError(tr("login_google_not_configured", "Google login sozlanmagan"));
      return;
    }

    if (!googleReady) {
      setError(tr("login_google_sdk_loading", "Google SDK yuklanmoqda, qayta bosing."));
      return;
    }

    triggerGoogleSignIn();
  };

  const handleUsernameChange = (value) => {
    userInteractedRef.current = true;
    setUsername(value);
  };

  const unlockInputs = useCallback(
    (element) => {
      userInteractedRef.current = true;
      if (inputsUnlocked) return;
      setInputsUnlocked(true);
      window.requestAnimationFrame(() => {
        element?.focus?.();
      });
    },
    [inputsUnlocked],
  );

  const applySavedUsername = () => {
    if (!savedUsername) return;
    userInteractedRef.current = true;
    setInputsUnlocked(true);
    setUsername(savedUsername);
    requestAnimationFrame(() => {
      usernameInputRef.current?.focus();
      usernameInputRef.current?.setSelectionRange(savedUsername.length, savedUsername.length);
    });
  };

  const handleSubmit = async (event) => {
    event.preventDefault();
    setError("");
    setLoading(true);

    try {
      const normalizedUsername = username.trim();
      if (!normalizedUsername || !password) {
        throw new Error(tr("error_required", "Fill all required fields"));
      }

      const formData = new FormData();
      formData.append("username", normalizedUsername);
      formData.append("password", password);
      if (profileInputRef.current?.files?.[0]) {
        formData.append("profilePic", profileInputRef.current.files[0]);
      }

      const res = await withTimeout(`${getBaseUrl()}/api/login`, {
        method: "POST",
        credentials: "include",
        body: formData,
      });

      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new Error(data.message || tr("login_failed", "Login failed"));
      }

      completeLogin(data.user);
    } catch (err) {
      setError(getRequestErrorMessage(err, tr("login_failed", "Login failed")));
    } finally {
      setLoading(false);
    }
  };

  const handleLanguageChange = (nextLang) => {
    changeLanguage(nextLang);
    navigate(`/${nextLang}/login`);
  };

  const handleProfilePick = () => {
    userInteractedRef.current = true;
    profileInputRef.current?.click();
  };

  const handleProfileChange = (event) => {
    const file = event.target.files?.[0];
    if (!file) {
      setProfilePreview("");
      return;
    }
    const previewUrl = URL.createObjectURL(file);
    setProfilePreview((current) => {
      if (current) URL.revokeObjectURL(current);
      return previewUrl;
    });
  };

  useEffect(() => {
    return () => {
      if (profilePreview) URL.revokeObjectURL(profilePreview);
    };
  }, [profilePreview]);

  const shellClass = isDark
    ? "bg-[linear-gradient(115deg,#07131d_0%,#0d2233_42%,#17374e_100%)] text-white"
    : "bg-[linear-gradient(135deg,#4fc6ff_0%,#2c7dfd_50%,#6f63ff_100%)] text-[#13202c]";

  const cardClass = isDark
    ? "bg-[#13202c] text-white shadow-[0_24px_70px_rgba(0,0,0,0.38)]"
    : "bg-[#f6f4fb] text-[#13202c] shadow-[0_24px_70px_rgba(43,124,255,0.18)]";

  const fieldClass = isDark
    ? "border border-white/12 bg-[#182430] text-white placeholder:text-white/35 shadow-[inset_0_1px_0_rgba(255,255,255,0.03)] focus:border-[#8fd1ff] focus:ring-[#8fd1ff]/20"
    : "border border-[#d4d8e5] bg-[#fbfaff] text-[#13202c] placeholder:text-[#9aa3b4] shadow-[0_8px_20px_rgba(90,120,170,0.08)] focus:border-[#8fbaf2] focus:ring-[#8fbaf2]/20";

  const mutedClass = isDark ? "text-white/72" : "text-[#677487]";
  const iconBoxClass = isDark
    ? "bg-[#00577a] text-[#8fd1ff]"
    : "bg-[#d7f0ff] text-[#1e88e5]";
  const googleButtonClass = isDark
    ? "border border-white/15 bg-[#182430] text-white hover:bg-[#1d2b38]"
    : "border border-[#1f2c44] bg-[#1f2c44] text-white hover:bg-[#263652]";

  const showSavedUsernameSuggestion =
    username.trim() &&
    savedUsername &&
    username.trim().toLowerCase() !== savedUsername.toLowerCase() &&
    savedUsername.toLowerCase().startsWith(username.trim().toLowerCase());

  return (
    <div
      className={`relative flex min-h-screen items-center justify-center overflow-hidden px-4 py-4 sm:py-6 ${shellClass}`}
    >
      <div className="absolute inset-0 bg-[radial-gradient(circle_at_top_left,rgba(55,145,210,0.28),transparent_34%),radial-gradient(circle_at_bottom_right,rgba(23,88,139,0.36),transparent_38%)]" />

      <div
        ref={formRootRef}
        className={`relative z-10 w-full max-w-md rounded-[24px] px-6 py-6 sm:px-7 sm:py-6 ${cardClass}`}
      >
        <div className="absolute right-5 top-5 shrink-0 sm:right-6 sm:top-6">
          <select
            value={LANGUAGE_OPTIONS.some((o) => o.value === lang) ? lang : "en"}
            onChange={(event) => handleLanguageChange(event.target.value)}
            className={`appearance-none bg-transparent pr-5 text-[17px] font-semibold outline-none ${isDark ? "text-white" : "text-[#233042]"}`}
          >
            {LANGUAGE_OPTIONS.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
          <i
            className={`fas fa-chevron-down pointer-events-none absolute right-0 top-1/2 -translate-y-1/2 text-xs ${mutedClass}`}
          />
        </div>

        <div
          className={`mx-auto flex h-[76px] w-[76px] items-center justify-center overflow-hidden rounded-[24px] ${iconBoxClass}`}
        >
          <img
            src={BRAND_LOGO_URL}
            alt="Bootchat logo"
            className="h-[46px] w-[46px] object-contain"
          />
        </div>

        <div className="mt-5 text-center">
          <h1 className="text-[28px] font-bold leading-none">{t("login_title")}</h1>
          <p className={`mt-2.5 text-[15px] ${mutedClass}`}>{t("login_subtitle")}</p>
        </div>

        <div className="mt-5 flex justify-center">
          <button
            type="button"
            onClick={handleProfilePick}
            className="group flex h-[108px] w-[108px] cursor-pointer items-center justify-center overflow-hidden rounded-full border-[4px] border-[#b8d8ff] bg-[#eef1f5] transition hover:scale-[1.02] hover:border-[#78b7ff]"
            title={tr("login_profile_pick", "Profil rasmini tanlash")}
          >
            {profilePreview ? (
              <img
                src={profilePreview}
                alt="Selected profile"
                className="h-full w-full object-cover"
              />
            ) : (
              <div className="flex flex-col items-center justify-center text-[#7f8b99]">
                <i className="fas fa-user-circle text-[68px]" />
                <span className="mt-1 text-[11px] font-semibold text-[#4d8fe6] opacity-0 transition group-hover:opacity-100">
                  Upload
                </span>
              </div>
            )}
          </button>
          <input
            ref={profileInputRef}
            type="file"
            accept="image/*"
            className="hidden"
            onChange={handleProfileChange}
          />
        </div>

        {error && (
          <div className="mt-6 rounded-[12px] bg-[#f8e9ea] px-5 py-4 text-center text-[14px] leading-7 text-[#de1f2f] whitespace-pre-line">
            {error}
          </div>
        )}

        <form onSubmit={handleSubmit} autoComplete="off" className="mt-6 space-y-4">
          <div className="hidden" aria-hidden="true">
            <input type="text" name="username" autoComplete="username" tabIndex={-1} />
            <input type="password" name="password" autoComplete="current-password" tabIndex={-1} />
          </div>

          <AuthField
            ref={usernameInputRef}
            value={username}
            onChange={(event) => handleUsernameChange(event.target.value)}
            onFocus={(event) => unlockInputs(event.currentTarget)}
            onPointerDown={(event) => unlockInputs(event.currentTarget)}
            label={tr("login_username_label", "Username")}
            icon="fa-user"
            name="bootchat_login_username"
            autoComplete="off"
            placeholder={tr("login_username_placeholder", "Username kiriting")}
            readOnly={!inputsUnlocked}
            fieldClass={fieldClass}
            mutedClass={mutedClass}
          />

          {showSavedUsernameSuggestion ? (
            <button
              type="button"
              onClick={applySavedUsername}
              className={`mt-[-8px] flex w-full items-center justify-between gap-3 rounded-[12px] border px-4 py-3 text-left transition-colors ${isDark ? "border-white/10 bg-[#182430] text-white hover:bg-[#1d2b38]" : "border-[#d4d8e5] bg-[#eef5ff] text-[#13202c] hover:bg-[#e4efff]"}`}
            >
              <div className="flex min-w-0 items-center gap-3">
                <i className={`fas fa-clock-rotate-left text-[15px] ${mutedClass}`} />
                <div className="min-w-0">
                  <div className={`text-[12px] ${mutedClass}`}>
                    {tr("login_saved_username_prompt", "Shuni xohlaysizmi?")}
                  </div>
                  <div className="truncate text-[15px] font-semibold">{savedUsername}</div>
                </div>
              </div>
              <span className="shrink-0 text-[13px] font-semibold text-[#2b7cff]">
                {tr("login_saved_username_apply", "Tanlash")}
              </span>
            </button>
          ) : null}

          <AuthField
            ref={passwordInputRef}
            value={password}
            onChange={(event) => {
              userInteractedRef.current = true;
              setPassword(event.target.value);
            }}
            onFocus={(event) => unlockInputs(event.currentTarget)}
            onPointerDown={(event) => unlockInputs(event.currentTarget)}
            label={tr("login_password_label", "Password")}
            icon="fa-lock"
            type={showPassword ? "text" : "password"}
            name="bootchat_login_password"
            autoComplete="new-password"
            placeholder={tr("login_password_placeholder", "Parol kiriting")}
            readOnly={!inputsUnlocked}
            fieldClass={fieldClass}
            mutedClass={mutedClass}
            rightSlot={
              <button
                type="button"
                onClick={() => setShowPassword((prev) => !prev)}
                className={`absolute right-5 top-1/2 -translate-y-1/2 text-[20px] ${mutedClass}`}
                aria-label={showPassword ? "Hide password" : "Show password"}
              >
                <i className={`fas ${showPassword ? "fa-eye-slash" : "fa-eye"}`} />
              </button>
            }
          />

          <button
            type="submit"
            disabled={loading}
            className="mt-1 flex h-[56px] w-full items-center justify-center gap-3 rounded-[12px] bg-[linear-gradient(90deg,#3c8cff_0%,#7064ff_52%,#b312ff_100%)] px-6 text-[18px] font-semibold text-white transition-transform hover:translate-y-[-1px] disabled:cursor-not-allowed disabled:opacity-70"
          >
            {loading ? (
              <i className="fas fa-spinner fa-spin text-[18px]" />
            ) : (
              <>
                <i className="fas fa-right-to-bracket text-[20px]" />
                <span>{tr("sign_in", t("login_button"))}</span>
              </>
            )}
          </button>
        </form>

        <div className="mt-5 flex items-center gap-3">
          <div className="h-px flex-1 bg-[#d8d8e2]" />
          <span className="rounded-full bg-[#f6f4fb] px-3 text-[14px] text-[#b2acb7]">yoki</span>
          <div className="h-px flex-1 bg-[#d8d8e2]" />
        </div>

        {/* ✅ Yashirin div olib tashlandi — custom button to'g'ridan-to'g'ri ishlaydi */}
        <div className="mt-4">
          <button
            type="button"
            onClick={handleGoogleLoginClick}
            disabled={googleLoading || !googleReady}
            className={`mt-2 flex h-[54px] w-full items-center justify-center gap-4 rounded-[14px] text-[16px] font-semibold transition-colors disabled:cursor-not-allowed disabled:opacity-70 ${googleButtonClass}`}
          >
            {googleLoading ? (
              <i className="fas fa-spinner fa-spin text-[18px]" />
            ) : (
              <>
                <i className="fab fa-google text-[20px] text-[#fbbc05]" />
                <span>{tr("sign_in_google", "Google orqali kirish")}</span>
              </>
            )}
          </button>
        </div>

        <div className="mt-5 flex justify-center">
          <Link
            to={`/${lang}/forgot-password`}
            className={`flex items-center gap-3 text-[15px] font-medium ${isDark ? "text-[#8fd1ff]" : "text-[#1e5fa6]"}`}
          >
            <i className="fas fa-clock-rotate-left text-[17px]" />
            <span>{tr("forgot_password", t("login_forgot_password"))}</span>
          </Link>
        </div>

        <div className="mt-7 flex flex-wrap items-center justify-center gap-x-3 gap-y-2 text-[15px]">
          <span className={mutedClass}>{tr("no_account", t("login_no_account"))}</span>
          <Link
            to={`/${lang}/signup`}
            className={`flex items-center gap-3 font-semibold ${isDark ? "text-[#8fd1ff]" : "text-[#1e5fa6]"}`}
          >
            <i className="fas fa-user-plus text-[17px]" />
            <span>{tr("sign_up", t("login_signup_link"))}</span>
          </Link>
        </div>
      </div>
    </div>
  );
}

const AuthField = forwardRef(function AuthField(
  {
    value,
    onChange,
    label,
    icon,
    name,
    placeholder,
    type = "text",
    autoComplete,
    onFocus,
    onPointerDown,
    readOnly = false,
    fieldClass,
    mutedClass,
    rightSlot,
  },
  ref,
) {
  return (
    <div>
      <label className={`mb-2 block text-[14px] font-semibold ${mutedClass}`}>{label}</label>
      <div className="relative">
        <i className={`fas ${icon} absolute left-5 top-1/2 -translate-y-1/2 text-[20px] ${mutedClass}`} />
        <input
          ref={ref}
          name={name}
          type={type}
          value={value}
          onChange={onChange}
          autoComplete={autoComplete}
          onFocus={onFocus}
          onPointerDown={onPointerDown}
          readOnly={readOnly}
          placeholder={placeholder}
          spellCheck={false}
          className={`h-[56px] w-full rounded-[12px] pl-[52px] pr-[52px] text-[17px] outline-none transition-colors focus:ring-2 caret-transparent ${fieldClass}`}
        />
        {rightSlot}
      </div>
    </div>
  );
});
