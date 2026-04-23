import { useState, useEffect, useCallback, useRef } from "react";
import { useNavigate, Link } from "react-router-dom";
import { useLanguage } from "@/context/LanguageContext";
import { useAuth } from "@/context/AuthContext";
import { BASE_URL } from "@/utils/api";

export default function SignupPage() {
  const LAST_LOGIN_USERNAME_KEY = "bootchat:last_login_username";
  const brandLogoUrl = `${BASE_URL}/static/imgs/chaqmoq.png`;
  const { t, lang } = useLanguage();
  const { login } = useAuth();
  const [form, setForm] = useState({
    fullName: "",
    username: "",
    phone: "",
    password: "",
    age: "",
    gender: true,
  });
  const [email, setEmail] = useState("");
  const [otpCode, setOtpCode] = useState("");
  const [otpStep, setOtpStep] = useState(false);
  const [otpSent, setOtpSent] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState("");
  const [info, setInfo] = useState("");
  const [loading, setLoading] = useState(false);
  const [resendLoading, setResendLoading] = useState(false);
  const [googleLoading, setGoogleLoading] = useState(false);
  const [googleReady, setGoogleReady] = useState(false);
  const [googleButtonRendered, setGoogleButtonRendered] = useState(false);
  const [inputsUnlocked, setInputsUnlocked] = useState(false);
  const googleButtonRef = useRef(null);
  const googleButtonInnerRef = useRef(null);
  const formRootRef = useRef(null);
  const userInteractedRef = useRef(false);
  const navigate = useNavigate();
  const GOOGLE_CLIENT_ID = import.meta.env.VITE_GOOGLE_CLIENT_ID || "";

  const tr = useCallback(
    (key, fallback) => {
      const value = t(key);
      return value === key ? fallback : value;
    },
    [t]
  );

  const completeLogin = useCallback(
    (userData) => {
      sessionStorage.removeItem("switch_to_user");
      localStorage.setItem(LAST_LOGIN_USERNAME_KEY, userData.username);
      if (userData.phone) localStorage.setItem("app_phone", userData.phone);
      if (userData.birthday) localStorage.setItem("app_birthday", userData.birthday);
      if (userData.bio) localStorage.setItem("app_bio", userData.bio);
      login(userData.username, userData.avatar || null, userData.fullName, userData.role);
      navigate(userData.role === "admin" ? `/${lang}/admin` : `/${lang}`);
    },
    [LAST_LOGIN_USERNAME_KEY, login, navigate, lang]
  );

  const handleGoogleCredential = useCallback(
    async (response) => {
      setError("");
      setInfo("");
      setGoogleLoading(true);
      try {
        const credential = response?.credential;
        if (!credential) {
          throw new Error(tr("login_google_failed", "Google orqali kirishda xatolik."));
        }

        const res = await fetch(`${BASE_URL}/api/login/google`, {
          method: "POST",
          credentials: "include",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ credential }),
        });

        const data = await res.json().catch(() => ({}));

        if (!res.ok) {
          if (res.status === 404) {
            throw new Error(
              tr("login_google_backend_missing", "Google login backend hali sozlanmagan.")
            );
          }
          throw new Error(
            data.message || tr("login_google_failed", "Google orqali kirishda xatolik.")
          );
        }

        if (!data?.user?.username) {
          throw new Error(
            tr("login_google_bad_response", "Google login javobi noto'g'ri formatda.")
          );
        }

        completeLogin(data.user);
      } catch (err) {
        setError(err.message || tr("login_google_failed", "Google orqali kirishda xatolik."));
      } finally {
        setGoogleLoading(false);
      }
    },
    [completeLogin, tr]
  );

  useEffect(() => {
    setGoogleReady(false);
    setGoogleButtonRendered(false);
    if (!GOOGLE_CLIENT_ID) return;

    let cancelled = false;
    const scriptId = "google-identity-service";

    const initGoogle = () => {
      if (cancelled) return;
      const gsi = window.google?.accounts?.id;
      if (!gsi) return;

      gsi.initialize({
        client_id: GOOGLE_CLIENT_ID,
        callback: handleGoogleCredential,
        auto_select: false,
        use_fedcm_for_prompt: false,
      });
      gsi.disableAutoSelect?.();
      setGoogleReady(true);
    };

    if (window.google?.accounts?.id) {
      initGoogle();
      return () => {
        cancelled = true;
      };
    }

    let script = document.getElementById(scriptId);
    const onLoad = () => initGoogle();

    if (!script) {
      script = document.createElement("script");
      script.id = scriptId;
      script.src = "https://accounts.google.com/gsi/client";
      script.async = true;
      script.defer = true;
      script.addEventListener("load", onLoad);
      document.head.appendChild(script);
    } else {
      script.addEventListener("load", onLoad);
    }

    return () => {
      cancelled = true;
      script?.removeEventListener("load", onLoad);
    };
  }, [GOOGLE_CLIENT_ID, handleGoogleCredential]);

  const clearVisibleAutofill = useCallback(() => {
    if (userInteractedRef.current) return;
    formRootRef.current?.querySelectorAll("input").forEach((input) => {
      input.value = "";
      input.blur?.();
    });
    if (document.activeElement instanceof HTMLElement) {
      document.activeElement.blur();
    }
    setForm({
      fullName: "",
      username: "",
      phone: "",
      password: "",
      age: "",
      gender: true,
    });
    setEmail("");
    setOtpCode("");
  }, []);

  useEffect(() => {
    const timers = [0, 150, 500].map((delay) =>
      window.setTimeout(clearVisibleAutofill, delay),
    );
    return () => {
      timers.forEach((timerId) => window.clearTimeout(timerId));
    };
  }, [clearVisibleAutofill]);

  useEffect(() => {
    if (!googleReady) return;
    const gsi = window.google?.accounts?.id;
    if (!gsi || !googleButtonRef.current) return;

    googleButtonRef.current.innerHTML = "";
    gsi.renderButton(googleButtonRef.current, {
      type: "standard",
      theme: "filled_black",
      size: "large",
      text: "signin_with",
      shape: "pill",
      logo_alignment: "left",
      width: googleButtonRef.current.offsetWidth || 320,
    });
    googleButtonInnerRef.current =
      googleButtonRef.current.querySelector("div[role=button], button");
    setGoogleButtonRendered(!!googleButtonInnerRef.current);
  }, [googleReady]);

  const handleGoogleLoginClick = () => {
    setError("");
    setInfo("");

    if (!GOOGLE_CLIENT_ID) {
      setError(tr("login_google_not_configured", "Google login sozlanmagan"));
      return;
    }

    if (!googleReady || !googleButtonRendered) {
      setError(
        tr("login_google_sdk_loading", "Google SDK yuklanmoqda, qayta bosing.")
      );
      return;
    }

    googleButtonInnerRef.current?.click();
  };

  const passwordChecks = [
    { label: t("signup_pw_min8"), test: (p) => p.length >= 8 },
    { label: t("signup_pw_letter"), test: (p) => /[A-Za-z]/.test(p) },
    { label: t("signup_pw_number"), test: (p) => /\d/.test(p) },
    { label: t("signup_pw_special"), test: (p) => /[!@#$%^&*()_+]/.test(p) },
  ];
  const isPasswordValid = passwordChecks.every((c) => c.test(form.password));

  const handleChange = (field) => (e) => {
    const value = field === "gender" ? e.target.value === "true" : e.target.value;
    userInteractedRef.current = true;
    setForm((prev) => ({ ...prev, [field]: value }));
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

  // Step 1 → Step 2 (faqat validatsiya, API chaqirmaydi)
  const handleNextStep = () => {
    if (!form.fullName || !form.username || !form.phone || !form.password || !form.age) {
      return setError(t("signup_fill_all"));
    }
    if (!isPasswordValid) return setError(t("signup_password_invalid"));
    setError("");
    setInfo("");
    setOtpStep(true);
  };

  // Step 2: Email kiritilgandan keyin OTP yuborish
  const handleSendOtp = async () => {
    if (!email.trim()) return setError(t("signup_email_required"));

    setError("");
    setInfo("");
    setLoading(true);
    try {
      const formData = new FormData();
      formData.append("fullName", form.fullName.trim());
      formData.append("username", form.username.trim());
      formData.append("phone", form.phone.trim());
      formData.append("email", email.trim());
      formData.append("password", form.password);
      formData.append("age", String(parseInt(form.age, 10)));
      formData.append("gender", String(form.gender));
      const res = await fetch(`${BASE_URL}/api/send-otp`, {
        method: "POST",
        body: formData,
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.message || "OTP failed");

      setOtpSent(true);
      setInfo(t("signup_otp_sent"));
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const handleVerifyOtp = async () => {
    if (!otpCode.trim()) return setError(t("signup_otp_enter"));

    setError("");
    setInfo("");
    setLoading(true);
    try {
      const res = await fetch(`${BASE_URL}/api/verify-otp`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email: email.trim(),
          code: otpCode.trim(),
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.message || "OTP failed");

      navigate(`/${lang}/login`);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const handleResendOtp = async () => {
    setError("");
    setInfo("");
    setResendLoading(true);
    try {
      const res = await fetch(`${BASE_URL}/api/resend-otp`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: email.trim() }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.message || "Resend failed");
      setInfo(t("signup_new_otp"));
    } catch (err) {
      setError(err.message);
    } finally {
      setResendLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-green-400 via-blue-500 to-purple-600 p-4">
      <div
        ref={formRootRef}
        className="w-full max-w-md bg-white/95 backdrop-blur-sm rounded-2xl shadow-2xl p-8"
      >
        <div className="hidden" aria-hidden="true">
          <input type="text" name="username" autoComplete="username" tabIndex={-1} />
          <input
            type="password"
            name="password"
            autoComplete="current-password"
            tabIndex={-1}
          />
        </div>
        <div className="text-center mb-5">
          <div className="mx-auto mb-3 flex h-16 w-16 items-center justify-center overflow-hidden rounded-2xl bg-gradient-to-br from-[#3390ec] to-[#2b7cd3] shadow-lg">
            <img
              src={brandLogoUrl}
              alt="Bootchat logo"
              className="h-10 w-10 object-contain"
            />
          </div>
          <h1 className="text-2xl font-bold text-gray-800">
            {otpStep ? t("signup_otp_title") : t("signup_title")}
          </h1>
          <p className="text-gray-500 text-sm mt-1">
            {otpStep ? t("signup_otp_subtitle") : t("signup_subtitle")}
          </p>
        </div>

        {error && (
          <div className="bg-red-50 text-red-600 p-3 rounded-lg mb-4 text-sm text-center">{error}</div>
        )}
        {info && (
          <div className="bg-blue-50 text-blue-700 p-3 rounded-lg mb-4 text-sm text-center">{info}</div>
        )}

        {!otpStep ? (
          <>
            <div className="space-y-3">
              <InputField icon="fa-user" name="bootchat_signup_fullname" autoComplete="off" readOnly={!inputsUnlocked} onFocus={(event) => unlockInputs(event.currentTarget)} onPointerDown={(event) => unlockInputs(event.currentTarget)} placeholder={t("signup_fullname")} value={form.fullName} onChange={handleChange("fullName")} />
              <InputField icon="fa-user" name="bootchat_signup_username" autoComplete="off" readOnly={!inputsUnlocked} onFocus={(event) => unlockInputs(event.currentTarget)} onPointerDown={(event) => unlockInputs(event.currentTarget)} placeholder={t("signup_username")} value={form.username} onChange={handleChange("username")} />
              <InputField icon="fa-phone" name="bootchat_signup_phone" autoComplete="off" readOnly={!inputsUnlocked} onFocus={(event) => unlockInputs(event.currentTarget)} onPointerDown={(event) => unlockInputs(event.currentTarget)} placeholder={t("signup_phone")} type="tel" value={form.phone} onChange={handleChange("phone")} />

              <div className="relative">
                <i className="fas fa-lock absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" />
                <input
                  name="bootchat_signup_password"
                  type={showPassword ? "text" : "password"}
                  value={form.password}
                  onChange={handleChange("password")}
                  onFocus={(event) => unlockInputs(event.currentTarget)}
                  onPointerDown={(event) => unlockInputs(event.currentTarget)}
                  autoComplete="new-password"
                  readOnly={!inputsUnlocked}
                  spellCheck={false}
                  className="w-full pl-10 pr-12 py-3 border border-gray-300 rounded-xl focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none text-sm text-gray-900 caret-transparent"
                  placeholder={t("signup_password")}
                />
                <button type="button" onClick={() => setShowPassword(!showPassword)} className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400">
                  <i className={`fas ${showPassword ? "fa-eye-slash" : "fa-eye"}`} />
                </button>
              </div>
              {form.password && (
                <div className="space-y-1 ml-1">
                  {passwordChecks.map((c, i) => (
                    <div key={i} className={`text-xs flex items-center gap-1 ${c.test(form.password) ? "text-green-600" : "text-gray-400"}`}>
                      <i className={`fas ${c.test(form.password) ? "fa-check-circle" : "fa-circle"} text-[10px]`} />
                      {c.label}
                    </div>
                  ))}
                </div>
              )}

              <div className="grid grid-cols-2 gap-3">
                <input
                  name="bootchat_signup_age"
                  type="number"
                  value={form.age}
                  onChange={handleChange("age")}
                  onFocus={(event) => unlockInputs(event.currentTarget)}
                  onPointerDown={(event) => unlockInputs(event.currentTarget)}
                  autoComplete="off"
                  readOnly={!inputsUnlocked}
                  spellCheck={false}
                  className="w-full px-4 py-3 border border-gray-300 rounded-xl focus:ring-2 focus:ring-blue-500 outline-none text-sm text-gray-900 caret-transparent"
                  placeholder={t("signup_age")}
                  min="1"
                  max="120"
                />
                <select
                  value={form.gender.toString()}
                  onChange={handleChange("gender")}
                  className="w-full px-4 py-3 border border-gray-300 rounded-xl focus:ring-2 focus:ring-blue-500 outline-none bg-white text-sm text-gray-900"
                >
                  <option value="true">{t("signup_male")}</option>
                  <option value="false">{t("signup_female")}</option>
                </select>
              </div>
            </div>

            <button
              onClick={handleNextStep}
              disabled={loading}
              className="w-full mt-5 py-3 bg-gradient-to-r from-blue-500 to-purple-600 text-white font-semibold rounded-xl hover:opacity-90 disabled:opacity-50 transition-opacity"
            >
              {t("signup_button")}
            </button>

            <div className="my-5 relative">
              <div className="h-px bg-gray-200" />
              <span className="absolute -top-2 left-1/2 -translate-x-1/2 bg-white px-3 text-xs text-gray-400">
                {tr("login_or", "yoki")}
              </span>
            </div>

            <div className="mt-5">
              <div
                ref={googleButtonRef}
                className="absolute -left-[9999px] top-0 h-0 w-0 overflow-hidden"
                aria-hidden="true"
              />
              <button
                type="button"
                onClick={handleGoogleLoginClick}
                disabled={googleLoading}
                className="w-full py-4 rounded-2xl bg-[#1f2a3d] hover:bg-[#24324a] text-white font-semibold transition-colors disabled:opacity-60 disabled:cursor-not-allowed flex items-center justify-center gap-3 shadow-lg"
              >
                <svg width="22" height="22" viewBox="0 0 48 48" aria-hidden="true">
                  <path fill="#FFC107" d="M43.611 20.083H42V20H24v8h11.303C33.654 32.657 29.236 36 24 36c-6.627 0-12-5.373-12-12s5.373-12 12-12c3.059 0 5.842 1.154 7.961 3.039l5.657-5.657C34.046 6.053 29.268 4 24 4 12.955 4 4 12.955 4 24s8.955 20 20 20 20-8.955 20-20c0-1.341-.138-2.65-.389-3.917z" />
                  <path fill="#FF3D00" d="M6.306 14.691l6.571 4.819C14.655 16.108 18.961 12 24 12c3.059 0 5.842 1.154 7.961 3.039l5.657-5.657C34.046 6.053 29.268 4 24 4 16.318 4 9.656 8.337 6.306 14.691z" />
                  <path fill="#4CAF50" d="M24 44c5.166 0 9.86-1.977 13.409-5.192l-6.19-5.238C29.144 35.091 26.68 36 24 36c-5.215 0-9.62-3.327-11.283-7.946l-6.522 5.025C9.505 39.556 16.227 44 24 44z" />
                  <path fill="#1976D2" d="M43.611 20.083H42V20H24v8h11.303a12.045 12.045 0 0 1-4.084 5.571h.003l6.19 5.238C36.971 39.164 44 34 44 24c0-1.341-.138-2.65-.389-3.917z" />
                </svg>
                {googleLoading
                  ? tr("login_google_loading", "Google orqali tekshirilmoqda...")
                  : tr("login_google_button", "Google orqali kirish")}
              </button>
            </div>
          </>
        ) : (
          <>
            <div className="space-y-3">
              <InputField
                icon="fa-envelope"
                name="bootchat_signup_email"
                autoComplete="off"
                readOnly={!inputsUnlocked}
                onFocus={(event) => unlockInputs(event.currentTarget)}
                onPointerDown={(event) => unlockInputs(event.currentTarget)}
                placeholder={t("signup_email")}
                type="email"
                value={email}
                onChange={(e) => {
                  userInteractedRef.current = true;
                  setEmail(e.target.value);
                }}
              />

              {!otpSent ? (
                <button
                  onClick={handleSendOtp}
                  disabled={loading}
                  className="w-full py-3 bg-gradient-to-r from-blue-500 to-purple-600 text-white font-semibold rounded-xl hover:opacity-90 disabled:opacity-50 transition-opacity"
                >
                  {loading ? <i className="fas fa-spinner fa-spin" /> : t("signup_send_otp")}
                </button>
              ) : (
                <>
                  <InputField
                    icon="fa-key"
                    name="bootchat_signup_otp"
                    autoComplete="off"
                    readOnly={!inputsUnlocked}
                    onFocus={(event) => unlockInputs(event.currentTarget)}
                    onPointerDown={(event) => unlockInputs(event.currentTarget)}
                    placeholder={t("signup_otp_enter")}
                    value={otpCode}
                    onChange={(e) => {
                      userInteractedRef.current = true;
                      setOtpCode(e.target.value.replace(/\D/g, "").slice(0, 6));
                    }}
                  />

                  <button
                    onClick={handleVerifyOtp}
                    disabled={loading}
                    className="w-full py-3 bg-gradient-to-r from-blue-500 to-purple-600 text-white font-semibold rounded-xl hover:opacity-90 disabled:opacity-50 transition-opacity"
                  >
                    {loading ? <i className="fas fa-spinner fa-spin" /> : t("signup_otp_button")}
                  </button>

                  <button
                    type="button"
                    onClick={handleResendOtp}
                    disabled={resendLoading}
                    className="w-full py-2.5 border border-blue-300 text-blue-700 rounded-xl hover:bg-blue-50 disabled:opacity-50"
                  >
                    {resendLoading ? "..." : t("signup_resend")}
                  </button>
                </>
              )}
            </div>
          </>
        )}

        <p className="text-center text-gray-500 mt-5 text-sm">
          {t("signup_has_account")}{" "}
          <Link to={`/${lang}/login`} className="text-blue-600 font-semibold hover:underline">{t("signup_login_link")}</Link>
        </p>
      </div>
    </div>
  );
}

function InputField({
  icon,
  type = "text",
  name,
  autoComplete = "off",
  readOnly = false,
  onFocus,
  onPointerDown,
  placeholder,
  value,
  onChange,
}) {
  return (
    <div className="relative">
      <i className={`fas ${icon} absolute left-3 top-1/2 -translate-y-1/2 text-gray-400`} />
      <input
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
        className="w-full pl-10 pr-4 py-3 border border-gray-300 rounded-xl focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none text-sm text-gray-900 caret-transparent"
      />
    </div>
  );
}
