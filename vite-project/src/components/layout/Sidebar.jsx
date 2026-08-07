import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "@/context/AuthContext";
import { useTheme } from "@/context/ThemeContext";
import { useLanguage } from "@/context/LanguageContext";
import Avatar from "@/components/common/Avatar";

export default function Sidebar({
  isOpen,
  onClose,
  onProfile,
  onContacts,
  onCalls,
  onSettings,
  onSavedMessages,
  onAdminDashboard,
}) {
  const { user, avatar, fullName, logout, isAdmin } = useAuth();
  const { isDark, toggleTheme } = useTheme();
  const { t, lang } = useLanguage();
  const [showAccountActions, setShowAccountActions] = useState(false);
  const navigate = useNavigate();
  const tr = (key, fallback) => {
    const value = t(key);
    return value === key ? fallback : value;
  };

  useEffect(() => {
    if (!isOpen) return;

    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";

    return () => {
      document.body.style.overflow = previousOverflow;
    };
  }, [isOpen]);

  useEffect(() => {
    if (isOpen) {
      setShowAccountActions(false);
    }
  }, [isOpen]);

  if (!isOpen) return null;

  const displayName = fullName || user || "Gujum";

  const handleLogout = async () => {
    await logout();
    onClose?.();
    navigate(`/${lang}/login`);
  };

  const handleAddAccount = () => {
    onClose?.();
    navigate(`/${lang}/login`);
  };

  const panelClass = isDark ? "bg-[#1f1f1f]" : "bg-[#f5f5f7]";
  const headerClass = isDark ? "bg-[#3f6280]" : "bg-[#5e89af]";
  const rowClass = isDark
    ? "border-b border-white/10 text-white hover:bg-white/5"
    : "border-b border-[#dde0e6] text-[#1e2430] hover:bg-black/[0.03]";
  const iconClass = isDark ? "text-white/80" : "text-[#303541]";
  return (
    <>
      <button
        type="button"
        aria-label="Close sidebar overlay"
        className="fixed inset-0 z-40 bg-black/30"
        onClick={onClose}
      />

      <aside
        className={`fixed inset-y-0 left-0 z-50 flex w-[85vw] max-w-[340px] flex-col overflow-hidden shadow-2xl animate-slideRight ${panelClass}`}
      >
        <div className={`px-7 pb-3 pt-6 ${headerClass}`}>
          <div className="flex items-start justify-between gap-4">
            <Avatar src={avatar} name={displayName} size={52} />
            <button
              type="button"
              onClick={() => setShowAccountActions((prev) => !prev)}
              className="mt-1 text-white/80 transition hover:text-white"
              aria-label="Toggle account actions"
            >
              <i
                className={`fas ${showAccountActions ? "fa-chevron-up" : "fa-chevron-down"} text-[17px]`}
              />
            </button>
          </div>
          <h3 className="mt-4 text-[15px] font-semibold text-white">
            {displayName}
          </h3>
        </div>

        <div className="flex-1 overflow-y-auto">
          {showAccountActions && (
            <SidebarItem
              icon="fa-circle-plus"
              label={tr("sidebar_add_account", "Add Account")}
              iconClass={iconClass}
              rowClass={rowClass}
              onClick={handleAddAccount}
            />
          )}

          <SidebarItem
            icon="fa-user"
            label={tr("sidebar_profile", "My Profile")}
            iconClass={iconClass}
            rowClass={rowClass}
            onClick={() => {
              onProfile?.();
              onClose?.();
            }}
          />

          <SidebarItem
            icon="fa-address-book"
            label={tr("sidebar_contacts", "Contacts")}
            iconClass={iconClass}
            rowClass={rowClass}
            onClick={() => {
              onContacts?.();
              onClose?.();
            }}
          />
          <SidebarItem
            icon="fa-phone"
            label={tr("sidebar_calls", "Calls")}
            iconClass={iconClass}
            rowClass={rowClass}
            onClick={() => {
              onCalls?.();
              onClose?.();
            }}
          />
          <SidebarItem
            icon="fa-bookmark"
            label={tr("sidebar_saved", "Saved Messages")}
            iconClass={iconClass}
            rowClass={rowClass}
            onClick={() => {
              onSavedMessages?.();
              onClose?.();
            }}
          />
          <SidebarItem
            icon="fa-cog"
            label={tr("sidebar_settings", "Settings")}
            iconClass={iconClass}
            rowClass={rowClass}
            onClick={() => {
              onSettings?.();
              onClose?.();
            }}
          />
          {isAdmin && (
            <SidebarItem
              icon="fa-chart-line"
              label={tr("admin_dashboard_title", "Admin Dashboard")}
              iconClass={iconClass}
              rowClass={rowClass}
              onClick={() => {
                onAdminDashboard?.();
                onClose?.();
              }}
            />
          )}

          <button
            type="button"
            onClick={toggleTheme}
            className={`flex w-full items-center justify-between px-7 py-4 text-left transition-colors ${rowClass}`}
          >
            <div className="flex items-center gap-5">
              <i
                className={`fas fa-moon w-6 text-center ${iconClass}`}
              />
              <span className="text-[15px]">
                {tr("sidebar_night_mode", "Night Mode")}
              </span>
            </div>
            <div
              className={`h-7 w-14 rounded-full p-1 transition-colors ${
                isDark ? "bg-[#7f95ac]" : "bg-[#c6c8ce]"
              }`}
            >
              <div
                className={`h-5 w-5 rounded-full bg-white shadow transition-transform ${
                  isDark ? "translate-x-7" : ""
                }`}
              />
            </div>
          </button>

        </div>

        <div className="border-t border-gray-200 p-3 dark:border-gray-700">
          <button
            type="button"
            onClick={handleLogout}
            className="flex w-full items-center gap-5 rounded-lg px-5 py-3 text-left text-red-500 transition-colors hover:bg-red-50 dark:hover:bg-red-900/20"
          >
            <i className="fas fa-sign-out-alt w-6 text-center" />
            <span className="text-[15px] font-medium">
              {t("sidebar_logout")}
            </span>
          </button>
          <p className="mt-2 text-center text-[11px] text-gray-400">
            Gujum
          </p>
        </div>
      </aside>
    </>
  );
}

function SidebarItem({ icon, label, onClick, iconClass, rowClass, badge = null }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`flex w-full items-center justify-between gap-5 px-7 py-4 text-left transition-colors ${rowClass}`}
    >
      <span className="flex items-center gap-5">
        <i className={`fas ${icon} w-6 text-center ${iconClass}`} />
        <span className="text-[15px]">{label}</span>
      </span>
      {badge ? (
        <span className="min-w-6 rounded-full bg-[#3390ec] px-2 py-0.5 text-center text-xs font-semibold text-white">
          {badge}
        </span>
      ) : null}
    </button>
  );
}
