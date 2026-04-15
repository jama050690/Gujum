import { useState } from "react";
import { useNavigate, Link } from "react-router-dom";
import { useLanguage } from "@/context/LanguageContext";
import { BASE_URL } from "@/utils/api";

export default function ForgotPasswordPage() {
  const { t, lang } = useLanguage();
  const [step, setStep] = useState("email"); // email | otp | done
  const [email, setEmail] = useState("");
  const [otpCode, setOtpCode] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState("");
  const [info, setInfo] = useState("");
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();

  const handleSendOtp = async () => {
    if (!email.trim()) return setError(t("forgot_enter_email"));
    setError("");
    setInfo("");
    setLoading(true);
    try {
      const res = await fetch(`${BASE_URL}/api/forgot-password`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: email.trim() }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.message || "Error");
      setStep("otp");
      setInfo(data.message);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const handleResetPassword = async () => {
    if (!otpCode.trim()) return setError(t("forgot_enter_otp"));
    if (!newPassword) return setError(t("forgot_enter_password"));
    setError("");
    setInfo("");
    setLoading(true);
    try {
      const res = await fetch(`${BASE_URL}/api/reset-password`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email: email.trim(),
          code: otpCode.trim(),
          newPassword,
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.message || "Error");
      setStep("done");
      setInfo(data.message);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-orange-400 via-red-500 to-pink-500 p-4">
      <div className="w-full max-w-md bg-white/95 backdrop-blur-sm rounded-2xl shadow-2xl p-8">
        <div className="text-center mb-6">
          <div className="w-16 h-16 mx-auto mb-3 rounded-2xl bg-gradient-to-br from-[#ef4444] to-[#f97316] flex items-center justify-center shadow-lg">
            <i className="fas fa-key text-white text-2xl" />
          </div>
          <h1 className="text-2xl font-bold text-gray-800">{t("forgot_title")}</h1>
          <p className="text-gray-500 text-sm mt-1">
            {step === "email" && t("forgot_step_email")}
            {step === "otp" && t("forgot_step_otp")}
            {step === "done" && t("forgot_step_done")}
          </p>
        </div>

        {error && (
          <div className="bg-red-50 text-red-600 p-3 rounded-lg mb-4 text-sm text-center">{error}</div>
        )}
        {info && (
          <div className="bg-blue-50 text-blue-700 p-3 rounded-lg mb-4 text-sm text-center">{info}</div>
        )}

        {step === "email" && (
          <>
            <div className="relative mb-4">
              <i className="fas fa-envelope absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" />
              <input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && handleSendOtp()}
                className="w-full pl-10 pr-4 py-3 border border-gray-300 rounded-xl focus:ring-2 focus:ring-red-500 focus:border-transparent outline-none text-gray-900"
                placeholder={t("forgot_email_placeholder")}
              />
            </div>
            <button
              onClick={handleSendOtp}
              disabled={loading}
              className="w-full py-3 bg-gradient-to-r from-red-500 to-orange-500 text-white font-semibold rounded-xl hover:opacity-90 transition-opacity disabled:opacity-50"
            >
              {loading ? <i className="fas fa-spinner fa-spin" /> : t("forgot_send_code")}
            </button>
          </>
        )}

        {step === "otp" && (
          <>
            <div className="space-y-3 mb-4">
              <div className="relative">
                <i className="fas fa-envelope absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" />
                <input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  className="w-full pl-10 pr-4 py-3 border border-gray-300 rounded-xl focus:ring-2 focus:ring-red-500 focus:border-transparent outline-none text-gray-900"
                  placeholder="Email"
                />
              </div>
              <div className="relative">
                <i className="fas fa-key absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" />
                <input
                  type="text"
                  value={otpCode}
                  onChange={(e) => setOtpCode(e.target.value.replace(/\D/g, "").slice(0, 6))}
                  className="w-full pl-10 pr-4 py-3 border border-gray-300 rounded-xl focus:ring-2 focus:ring-red-500 focus:border-transparent outline-none text-gray-900"
                  placeholder={t("forgot_enter_otp")}
                />
              </div>
              <div className="relative">
                <i className="fas fa-lock absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" />
                <input
                  type={showPassword ? "text" : "password"}
                  value={newPassword}
                  onChange={(e) => setNewPassword(e.target.value)}
                  className="w-full pl-10 pr-12 py-3 border border-gray-300 rounded-xl focus:ring-2 focus:ring-red-500 focus:border-transparent outline-none text-gray-900"
                  placeholder={t("forgot_new_password")}
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600"
                >
                  <i className={`fas ${showPassword ? "fa-eye-slash" : "fa-eye"}`} />
                </button>
              </div>
            </div>
            <button
              onClick={handleResetPassword}
              disabled={loading}
              className="w-full py-3 bg-gradient-to-r from-red-500 to-orange-500 text-white font-semibold rounded-xl hover:opacity-90 transition-opacity disabled:opacity-50"
            >
              {loading ? <i className="fas fa-spinner fa-spin" /> : t("forgot_update_button")}
            </button>
            <button
              onClick={handleSendOtp}
              disabled={loading}
              className="w-full mt-2 py-2.5 border border-red-300 text-red-700 rounded-xl hover:bg-red-50 disabled:opacity-50"
            >
              {t("forgot_resend")}
            </button>
          </>
        )}

        {step === "done" && (
          <button
            onClick={() => navigate(`/${lang}/login`)}
            className="w-full py-3 bg-gradient-to-r from-green-500 to-emerald-500 text-white font-semibold rounded-xl hover:opacity-90 transition-opacity"
          >
            {t("forgot_go_login")}
          </button>
        )}

        <p className="text-center text-gray-500 mt-6 text-sm">
          <Link to={`/${lang}/login`} className="text-blue-600 font-semibold hover:underline">
            {t("forgot_back_login")}
          </Link>
        </p>
      </div>
    </div>
  );
}
