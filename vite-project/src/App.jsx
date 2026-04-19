import { useEffect } from "react";
import { initAudio } from "@/utils/sounds";
import { BrowserRouter, Routes, Route, Navigate, Outlet, useParams } from "react-router-dom";
import { AuthProvider, useAuth } from "@/context/AuthContext";
import { ThemeProvider } from "@/context/ThemeContext";
import { LanguageProvider, SUPPORTED_LANGS, useLanguage } from "@/context/LanguageContext";
import { SocketProvider } from "@/context/SocketContext";
import { ChatProvider } from "@/context/ChatContext";
import LoginPage from "@/pages/LoginPage";
import SignupPage from "@/pages/SignupPage";
import ForgotPasswordPage from "@/pages/ForgotPasswordPage";
import ChatPage from "@/pages/ChatPage";

function ProtectedRoute({ children }) {
  const { isAuthenticated, user } = useAuth();
  const { lang } = useLanguage();
  if (!isAuthenticated) return <Navigate to={`/${lang}/login`} replace />;

  return (
    <SocketProvider username={user}>
      <ChatProvider>
        {children}
      </ChatProvider>
    </SocketProvider>
  );
}

function PublicRoute({ children }) {
  const { isAuthenticated } = useAuth();
  const { lang } = useLanguage();
  if (isAuthenticated) return <Navigate to={`/${lang}`} replace />;
  return children;
}

// URL'dagi til prefiksini LanguageContext bilan sinxronlash (/en, /uz, /ru ...)
function LanguageLayout() {
  const { lang } = useParams();
  const { changeLanguage } = useLanguage();

  useEffect(() => {
    if (SUPPORTED_LANGS.includes(lang)) {
      changeLanguage(lang);
    }
  }, [lang, changeLanguage]);

  if (!SUPPORTED_LANGS.includes(lang)) {
    return <LangRedirect to="" />;
  }

  return <Outlet />;
}

// Eski URL'larni /:lang/ prefiksiga yo'naltirish
function LangRedirect({ to }) {
  const { lang } = useLanguage();
  return <Navigate to={`/${lang}${to}`} replace />;
}

export default function App() {
  // Initialize audio context on first user interaction to enable sounds
  useEffect(() => {
    const handleInteraction = () => {
      initAudio();
      window.removeEventListener("click", handleInteraction);
      window.removeEventListener("keydown", handleInteraction);
      window.removeEventListener("touchstart", handleInteraction);
    };

    window.addEventListener("click", handleInteraction);
    window.addEventListener("keydown", handleInteraction);
    window.addEventListener("touchstart", handleInteraction);

    return () => {
      window.removeEventListener("click", handleInteraction);
      window.removeEventListener("keydown", handleInteraction);
      window.removeEventListener("touchstart", handleInteraction);
    };
  }, []);

  return (
    <BrowserRouter basename={import.meta.env.VITE_BASE_PATH || "/"}>
      <AuthProvider>
        <LanguageProvider>
          <ThemeProvider>
            <Routes>
              {/* Til prefiksli route'lar: /en, /uz, /ru/login ... */}
              <Route path="/:lang" element={<LanguageLayout />}>
                <Route path="login" element={<PublicRoute><LoginPage /></PublicRoute>} />
                <Route path="signup" element={<PublicRoute><SignupPage /></PublicRoute>} />
                <Route path="forgot-password" element={<PublicRoute><ForgotPasswordPage /></PublicRoute>} />
                <Route index element={<ProtectedRoute><ChatPage /></ProtectedRoute>} />
              </Route>

              {/* Eski URL'lar — avtomatik tilga yo'naltirish */}
              <Route path="/login" element={<LangRedirect to="/login" />} />
              <Route path="/signup" element={<LangRedirect to="/signup" />} />
              <Route path="/forgot-password" element={<LangRedirect to="/forgot-password" />} />
              <Route path="/" element={<LangRedirect to="" />} />
              <Route path="*" element={<LangRedirect to="" />} />
            </Routes>
          </ThemeProvider>
        </LanguageProvider>
      </AuthProvider>
    </BrowserRouter>
  );
}
