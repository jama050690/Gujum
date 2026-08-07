import { createContext, useContext, useState, useEffect } from "react";
import { isDarkMode, setDarkMode } from "@/utils/storage";

const ThemeContext = createContext(null);

export function ThemeProvider({ children }) {
  const [isDark, setIsDark] = useState(isDarkMode());

  useEffect(() => {
    document.documentElement.classList.toggle("dark_mode", isDark);
    document.documentElement.classList.toggle("light_mode", !isDark);
  }, [isDark]);

  const toggleTheme = () => {
    setIsDark((prev) => {
      setDarkMode(!prev);
      return !prev;
    });
  };

  return (
    <ThemeContext.Provider value={{ isDark, toggleTheme }}>
      {children}
    </ThemeContext.Provider>
  );
}

export function useTheme() {
  const ctx = useContext(ThemeContext);
  if (!ctx) throw new Error("useTheme must be used within ThemeProvider");
  return ctx;
}
