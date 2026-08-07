import { createContext, useContext, useState } from "react";
import {
  getUser, getAvatar, getRole, setAuth, clearAuth, getProfileData, saveProfileData,
  getAccounts, saveAccountSnapshot, restoreAccount, removeAccount as removeStoredAccount,
} from "@/utils/storage";
import { getBaseUrl } from "@/utils/api";

const AuthContext = createContext(null);

export function AuthProvider({ children }) {
  const [user, setUser] = useState(getUser());
  const [avatar, setAvatar] = useState(getAvatar());
  const [role, setRole] = useState(getRole());
  const [fullName, setFullName] = useState(getProfileData().fullName);
  const [accounts, setAccounts] = useState(getAccounts());

  const refreshAccounts = () => setAccounts(getAccounts());

  const login = (username, avatarUrl, fullNameVal, roleVal = "user") => {
    setAuth(username, avatarUrl, roleVal);
    setUser(username);
    setAvatar(avatarUrl);
    setRole(roleVal || "user");
    if (fullNameVal) saveProfileData({ fullName: fullNameVal });
    setFullName(fullNameVal || username);
    saveAccountSnapshot();
    refreshAccounts();
  };

  const logout = () => {
    fetch(`${getBaseUrl()}/api/logout`, {
      method: "POST",
      credentials: "include",
    }).catch(() => {});
    clearAuth();
    setUser(null);
    setAvatar(null);
    setRole("user");
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
    setRole(acc.role || "user");
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
    saveProfileData({ fullName: name });
    setFullName(name);
  };

  return (
    <AuthContext.Provider value={{
      user, avatar, fullName, accounts,
      role,
      login, logout, addAccount, switchAccount, removeAccountByName,
      updateAvatar, updateFullName,
      isAuthenticated: !!user,
      isAdmin: role === "admin",
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
