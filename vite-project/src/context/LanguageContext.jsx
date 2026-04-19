import { createContext, useContext, useState, useCallback } from "react";
import { translations } from "@/i18n/translations";

const LanguageContext = createContext();

export const SUPPORTED_LANGS = Object.keys(translations);

export function LanguageProvider({ children }) {
  const [lang, setLang] = useState(() => {
    // URL'dan tilni aniqlash (masalan: /bootchat/en)
    const basePath = (import.meta.env.VITE_BASE_PATH || "/").replace(/\/$/, "");
    const pathname = window.location.pathname;
    const afterBase = pathname.startsWith(basePath) ? pathname.slice(basePath.length) : pathname;
    const firstSegment = afterBase.replace(/^\//, "").split("/")[0];

    if (firstSegment && SUPPORTED_LANGS.includes(firstSegment)) {
      localStorage.setItem("app_language", firstSegment);
      return firstSegment;
    }

    return localStorage.getItem("app_language") || "uz";
  });

  const changeLanguage = useCallback((code) => {
    setLang(code);
    localStorage.setItem("app_language", code);
  }, []);

  const t = useCallback(
    (key) => {
      const dict = translations[lang] || translations.uz;
      return dict[key] || translations.uz[key] || key;
    },
    [lang]
  );

  return (
    <LanguageContext.Provider value={{ lang, changeLanguage, t }}>
      {children}
    </LanguageContext.Provider>
  );
}

export function useLanguage() {
  const ctx = useContext(LanguageContext);
  if (!ctx) throw new Error("useLanguage must be used within LanguageProvider");
  return ctx;
}
