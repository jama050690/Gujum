import { useEffect } from "react";
import { BrowserRouter, Routes, Route, Navigate, Outlet, useParams } from "react-router-dom";
import { AuthProvider, useAuth } from "@/context/AuthContext";
import { ThemeProvider } from "@/context/ThemeContext";
import { LanguageProvider, SUPPORTED_LANGS, useLanguage } from "@/context/LanguageContext";
import { SocketProvider } from "@/context/SocketContext";
import { ChatProvider } from "@/context/ChatContext";
import { initAudio } from "@/utils/sounds";

// Sahifalar
import LoginPage from "@/pages/LoginPage";
import SignupPage from "@/pages/SignupPage";
import ForgotPasswordPage from "@/pages/ForgotPasswordPage";
import ChatPage from "@/pages/ChatPage";
import AdminDashboardPage from "@/pages/AdminDashboardPage";

// Himoyalangan marshrut (Faqat login qilganlar uchun)
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

// Admin marshrut
function AdminRoute({ children }) {
  const { isAuthenticated, isAdmin } = useAuth();
  const { lang } = useLanguage();
  
  if (!isAuthenticated) return <Navigate to={`/${lang}/login`} replace />;
  if (!isAdmin) return <Navigate to={`/${lang}`} replace />;
  
  return children;
}

// Ochiq marshrut (Login qilganlar bu yerga kira olmaydi)
function PublicRoute({ children }) {
  const { isAuthenticated, isAdmin } = useAuth();
  const { lang } = useLanguage();
  
  if (isAuthenticated) {
    return <Navigate to={isAdmin ? `/${lang}/admin` : `/${lang}`} replace />;
  }
  return children;
}

// Til prefiksini sinxronlash layouts
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

// Tilga yo'naltirish yordamchisi
function LangRedirect({ to }) {
  const { lang } = useLanguage();
  return <Navigate to={`/${lang}${to}`} replace />;
}

export default function App() {
  // --- AUDIO INITIALIZATION ---
  // Foydalanuvchi birinchi marta ekranga tekkanda ovoz tizimi ishga tushadi
  useEffect(() => {
    const handleInteraction = async () => {
      try {
        await initAudio();
        console.log("✅ AudioContext faollashtirildi");
        
        // Eventlarni tozalash
        window.removeEventListener("click", handleInteraction);
        window.removeEventListener("keydown", handleInteraction);
        window.removeEventListener("touchstart", handleInteraction);
      } catch (error) {
        console.error("Audio init error:", error);
      }
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
              {/* Asosiy til prefiksli marshrutlar */}
              <Route path="/:lang" element={<LanguageLayout />}>
                <Route path="login" element={<PublicRoute><LoginPage /></PublicRoute>} />
                <Route path="signup" element={<PublicRoute><SignupPage /></PublicRoute>} />
                <Route path="forgot-password" element={<PublicRoute><ForgotPasswordPage /></PublicRoute>} />
                <Route path="admin" element={<AdminRoute><AdminDashboardPage /></AdminRoute>} />
                <Route index element={<ProtectedRoute><ChatPage /></ProtectedRoute>} />
              </Route>

              {/* Prefikssiz kelgan eski URL'larni avtomatik yo'naltirish */}
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