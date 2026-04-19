import { createContext, useContext, useState } from "react";
import {
  getUser, getAvatar, setAuth, clearAuth,
  getAccounts, saveAccountSnapshot, restoreAccount, removeAccount as removeStoredAccount,
} from "@/utils/storage";

const AuthContext = createContext(null);

export function AuthProvider({ children }) {
  const [user, setUser] = useState(getUser());
  const [avatar, setAvatar] = useState(getAvatar());
  const [fullName, setFullName] = useState(localStorage.getItem("app_fullname"));
  const [accounts, setAccounts] = useState(getAccounts());

  const refreshAccounts = () => setAccounts(getAccounts());

  const login = (username, avatarUrl, fullNameVal) => {
    setAuth(username, avatarUrl);
    setUser(username);
    setAvatar(avatarUrl);
    if (fullNameVal) localStorage.setItem("app_fullname", fullNameVal);
    setFullName(fullNameVal || username);
    saveAccountSnapshot();
    refreshAccounts();
  };

  const logout = () => {
    clearAuth();
    localStorage.removeItem("app_fullname");
    setUser(null);
    setAvatar(null);
    setFullName(null);
  };

  // Save current account, clear auth, go to login (caller navigates)
  const addAccount = () => {
    saveAccountSnapshot();
    refreshAccounts();
    logout();
  };

  // Switch to another saved account
  const switchAccount = (username) => {
    saveAccountSnapshot(); // save current first
    const acc = restoreAccount(username);
    if (!acc) return false;
    setUser(acc.username);
    setAvatar(acc.avatar);
    setFullName(acc.fullName || acc.username);
    refreshAccounts();
    return true;
  };

  // Remove a saved account
  const removeAccountByName = (username) => {
    removeStoredAccount(username);
    refreshAccounts();
  };

  const updateAvatar = (newAvatar) => {
    localStorage.setItem("app_avatar", newAvatar);
    setAvatar(newAvatar);
  };

  const updateFullName = (name) => {
    localStorage.setItem("app_fullname", name);
    setFullName(name);
  };

  return (
    <AuthContext.Provider value={{
      user, avatar, fullName, accounts,
      login, logout, addAccount, switchAccount, removeAccountByName,
      updateAvatar, updateFullName,
      isAuthenticated: !!user,
    }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used within AuthProvider");
  return ctx;
}
