import { useState, useEffect, useRef } from "react";
import { useNavigate } from "react-router-dom";
import { useTheme } from "@/context/ThemeContext";
import { useAuth } from "@/context/AuthContext";
import { useLanguage } from "@/context/LanguageContext";
import { getSettings, saveSetting, getProfileData, KEYS } from "@/utils/storage";
import { fetchJSON, BASE_URL } from "@/utils/api";
import Modal from "./Modal";
import Avatar from "../common/Avatar";

const SECTIONS = [
  { id: "account", icon: "fa-user-circle", labelKey: "settings_my_account", color: "text-blue-500" },
  { id: "notifications", icon: "fa-bell", labelKey: "settings_notifications", color: "text-orange-500" },
  { id: "privacy", icon: "fa-lock", labelKey: "settings_privacy", color: "text-green-500" },
  { id: "chat", icon: "fa-comment-dots", labelKey: "settings_chat", color: "text-purple-500" },
  { id: "folders", icon: "fa-folder", labelKey: "settings_folders", color: "text-yellow-500" },
  { id: "advanced", icon: "fa-sliders-h", labelKey: "settings_advanced", color: "text-gray-500" },
  { id: "speakers", icon: "fa-volume-up", labelKey: "settings_speakers", color: "text-teal-500" },
  { id: "battery", icon: "fa-battery-full", labelKey: "settings_battery", color: "text-lime-500" },
];

export default function SettingsModal({ isOpen, onClose }) {
  const { isDark, toggleTheme } = useTheme();
  const { user, avatar, logout, addAccount, removeAccountByName } = useAuth();
  const { t, lang } = useLanguage();
  const navigate = useNavigate();
  const [activeSection, setActiveSection] = useState(null);
  const settings = getSettings();
  const profile = getProfileData();

  const [interfaceScale, setInterfaceScale] = useState(
    () => parseInt(localStorage.getItem("app_interface_scale") || "100")
  );

  const handleScaleChange = (val) => {
    const v = parseInt(val);
    setInterfaceScale(v);
    localStorage.setItem("app_interface_scale", v.toString());
    document.documentElement.style.fontSize = `${v}%`;
  };

  if (!isOpen) return null;

  if (activeSection) {
    return (
      <Modal isOpen={isOpen} onClose={onClose} title="" className="max-w-lg">
        <div className="px-5 py-4 border-b border-gray-200 dark:border-gray-700 flex items-center gap-3 shrink-0">
          <button
            onClick={() => setActiveSection(null)}
            className="p-1.5 text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-white hover:bg-gray-100 dark:hover:bg-gray-800 rounded-lg"
          >
            <i className="fas fa-arrow-left" />
          </button>
          <h3 className="text-lg font-bold text-gray-900 dark:text-white">
            {activeSection === "language" ? t("settings_language") : (SECTIONS.find((s) => s.id === activeSection)?.labelKey ? t(SECTIONS.find((s) => s.id === activeSection).labelKey) : t("settings_title"))}
          </h3>
          <button onClick={onClose} className="ml-auto p-1.5 text-gray-400 hover:text-gray-600 hover:bg-gray-100 dark:hover:bg-gray-800 rounded-lg">
            <i className="fas fa-times" />
          </button>
        </div>
        <div className="p-4">
          <SectionContent section={activeSection} settings={settings} profile={profile} />
        </div>
      </Modal>
    );
  }

  return (
    <Modal isOpen={isOpen} onClose={onClose} title="" className="max-w-lg">
      {/* Custom header with menu icons */}
      <div className="flex items-center justify-between px-5 py-4 border-b border-gray-200 dark:border-gray-700 shrink-0">
        <h3 className="text-lg font-bold text-gray-900 dark:text-white">{t("settings_title")}</h3>
        <div className="flex items-center gap-2">
          <button className="p-1.5 text-gray-400 hover:text-gray-600 hover:bg-gray-100 dark:hover:bg-gray-800 rounded-lg">
            <i className="fas fa-th" />
          </button>
          <button className="p-1.5 text-gray-400 hover:text-gray-600 hover:bg-gray-100 dark:hover:bg-gray-800 rounded-lg">
            <i className="fas fa-ellipsis-v" />
          </button>
          <button onClick={onClose} className="p-1.5 text-gray-400 hover:text-gray-600 hover:bg-gray-100 dark:hover:bg-gray-800 rounded-lg">
            <i className="fas fa-times" />
          </button>
        </div>
      </div>

      <div className="p-4">
        {/* Profile section */}
        <button
          onClick={() => setActiveSection("account")}
          className="w-full flex items-center gap-3 p-3 rounded-xl hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors mb-3"
        >
          <Avatar src={avatar} alt={user} size={50} />
          <div className="text-left flex-1 min-w-0">
            <div className="font-semibold text-gray-900 dark:text-white truncate">
              {profile.phone ? user : user}
            </div>
            {profile.phone && (
              <div className="text-sm text-gray-500 dark:text-gray-400">{profile.phone}</div>
            )}
            <div className="text-sm text-gray-400 dark:text-gray-500">@{user}</div>
          </div>
        </button>

        <div className="border-t border-gray-100 dark:border-gray-700 my-2" />

        {/* Sections */}
        <div className="space-y-0.5">
          {SECTIONS.map((s) => (
            <button
              key={s.id}
              onClick={() => setActiveSection(s.id)}
              className="w-full flex items-center gap-3 px-3 py-2.5 rounded-xl hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors"
            >
              <i className={`fas ${s.icon} w-6 text-center ${s.color}`} />
              <span className="text-sm font-medium text-gray-900 dark:text-white">{t(s.labelKey)}</span>
            </button>
          ))}

          {/* Language - separate */}
          <button
            onClick={() => setActiveSection("language")}
            className="w-full flex items-center gap-3 px-3 py-2.5 rounded-xl hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors"
          >
            <i className="fas fa-language w-6 text-center text-cyan-500" />
            <span className="text-sm font-medium text-gray-900 dark:text-white">{t("settings_language")}</span>
          </button>
        </div>

        <div className="border-t border-gray-100 dark:border-gray-700 my-3" />

        {/* Interface scale */}
        <div className="px-3">
          <div className="flex items-center justify-between mb-2">
            <div className="flex items-center gap-3">
              <i className="fas fa-eye w-6 text-center text-gray-500" />
              <span className="text-sm font-medium text-gray-900 dark:text-white">{t("settings_interface_scale")}</span>
            </div>
            <div className="flex items-center gap-2">
              <label className="relative inline-flex items-center cursor-pointer">
                <input
                  type="checkbox"
                  checked={interfaceScale !== 100}
                  onChange={(e) => handleScaleChange(e.target.checked ? 125 : 100)}
                  className="sr-only peer"
                />
                <div className="w-9 h-5 bg-gray-300 peer-checked:bg-blue-500 rounded-full transition-colors after:content-[''] after:absolute after:top-0.5 after:left-[2px] peer-checked:after:translate-x-full after:bg-white after:rounded-full after:h-4 after:w-4 after:transition-transform" />
              </label>
            </div>
          </div>
          <div className="flex items-center gap-3 ml-9">
            <input
              type="range"
              min="75"
              max="150"
              step="25"
              value={interfaceScale}
              onChange={(e) => handleScaleChange(e.target.value)}
              className="flex-1 h-1.5 bg-gray-200 dark:bg-gray-700 rounded-full appearance-none cursor-pointer accent-blue-500"
            />
            <span className="text-sm font-medium text-blue-500 w-10 text-right">{interfaceScale}%</span>
          </div>
        </div>

        <div className="border-t border-gray-100 dark:border-gray-700 my-3" />

        {/* Dark mode toggle */}
        <button
          onClick={toggleTheme}
          className="w-full flex items-center gap-3 px-3 py-2.5 rounded-xl hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors"
        >
          <i className={`fas ${isDark ? "fa-moon" : "fa-sun"} w-6 text-center text-yellow-500`} />
          <span className="text-sm font-medium text-gray-900 dark:text-white">
            {isDark ? t("sidebar_night_mode") : t("sidebar_day_mode")}
          </span>
          <div className={`ml-auto w-9 h-5 rounded-full p-0.5 transition-colors ${isDark ? "bg-blue-500" : "bg-gray-300"}`}>
            <div className={`w-4 h-4 rounded-full bg-white transition-transform ${isDark ? "translate-x-4" : ""}`} />
          </div>
        </button>

        {/* Add Account */}
        <button
          onClick={() => { addAccount(); onClose(); navigate(`/${lang}/login`); }}
          className="w-full flex items-center gap-3 px-3 py-2.5 mt-2 rounded-xl hover:bg-blue-50 dark:hover:bg-blue-900/20 text-blue-500 transition-colors"
        >
          <i className="fas fa-plus-circle w-6 text-center" />
          <span className="text-sm font-medium">{t("sidebar_add_account")}</span>
        </button>

        {/* Logout */}
        <button
          onClick={() => { removeAccountByName(user); logout(); onClose(); navigate(`/${lang}/login`); }}
          className="w-full flex items-center gap-3 px-3 py-2.5 rounded-xl hover:bg-red-50 dark:hover:bg-red-900/20 text-red-500 transition-colors"
        >
          <i className="fas fa-sign-out-alt w-6 text-center" />
          <span className="text-sm font-medium">{t("sidebar_logout")}</span>
        </button>
      </div>
    </Modal>
  );
}

function SectionContent({ section, settings, profile }) {
  const { t } = useLanguage();
  switch (section) {
    case "account":
      return <AccountSection profile={profile} />;
    case "notifications":
      return <NotificationsSection />;
    case "privacy":
      return <PrivacySection />;
    case "chat":
      return <ChatSection settings={settings} />;
    case "folders":
      return <FoldersSection />;
    case "advanced":
      return <AdvancedSection />;
    case "speakers":
      return <SpeakersSection />;
    case "battery":
      return <BatterySection />;
    case "language":
      return <LanguageSection />;
    default:
      return <p className="text-gray-500 text-sm text-center py-8">{t("settings_coming_soon")}</p>;
  }
}

function SettingToggle({ label, description, checked, onChange }) {
  return (
    <div className="flex items-center justify-between py-3">
      <div className="flex-1 min-w-0 mr-3">
        <div className="text-sm font-medium text-gray-900 dark:text-white">{label}</div>
        {description && <div className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">{description}</div>}
      </div>
      <button
        onClick={() => onChange(!checked)}
        className={`w-9 h-5 rounded-full p-0.5 transition-colors shrink-0 ${checked ? "bg-blue-500" : "bg-gray-300"}`}
      >
        <div className={`w-4 h-4 rounded-full bg-white transition-transform ${checked ? "translate-x-4" : ""}`} />
      </button>
    </div>
  );
}

function AccountSection({ profile }) {
  const { user, avatar, fullName, updateAvatar, addAccount } = useAuth();
  const { t, lang } = useLanguage();
  const navigate = useNavigate();
  const [bio, setBio] = useState(profile.bio || "");
  const maxBio = 70;
  const avatarInputRef = useRef(null);

  const handleAvatarUpload = async (e) => {
    const file = e.target.files[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = (ev) => updateAvatar(ev.target.result);
    reader.readAsDataURL(file);
    const formData = new FormData();
    formData.append("avatar", file);
    try {
      const res = await fetch(`${BASE_URL}/api/users/profile`, {
        method: "PUT",
        credentials: "include",
        body: formData,
      });
      const data = await res.json();
      if (data.avatar) updateAvatar(data.avatar);
    } catch (err) {
      console.error("Avatar yuklashda xato:", err);
    }
  };

  const handleBioSave = async () => {
    localStorage.setItem("app_bio", bio);
    try {
      await fetchJSON("/api/users/profile", {
        method: "PUT",
        body: JSON.stringify({ bio }),
      });
    } catch (err) {
      console.error("Bio saqlashda xato:", err);
    }
  };

  return (
    <div>
      {/* Avatar + name */}
      <div className="flex flex-col items-center py-5">
        <div className="relative" onClick={() => avatarInputRef.current?.click()}>
          <Avatar src={avatar} alt={user} size={100} />
          <div className="absolute bottom-0 right-0 w-8 h-8 bg-blue-500 rounded-full flex items-center justify-center border-2 border-white dark:border-gray-900 cursor-pointer">
            <i className="fas fa-camera text-white text-xs" />
          </div>
          <input ref={avatarInputRef} type="file" accept="image/*" className="hidden" onChange={handleAvatarUpload} />
        </div>
        <div className="mt-3 text-xl font-semibold text-gray-900 dark:text-white">{fullName || user}</div>
        <div className="text-sm text-blue-500">{t("online")}</div>
      </div>

      {/* Bio */}
      <div className="border-t border-gray-100 dark:border-gray-700">
        <div className="px-4 py-3">
          <div className="flex items-center justify-between mb-1">
            <span className="text-sm text-blue-500">{t("settings_bio")}</span>
            <span className="text-xs text-gray-400">{maxBio - bio.length}</span>
          </div>
          <input
            type="text"
            value={bio}
            onChange={(e) => { if (e.target.value.length <= maxBio) setBio(e.target.value); }}
            onBlur={handleBioSave}
            placeholder={t("settings_bio_placeholder")}
            className="w-full text-sm text-gray-900 dark:text-white bg-transparent outline-none placeholder-gray-400"
          />
        </div>
        <p className="px-4 pb-3 text-xs text-gray-400 dark:text-gray-500">
          {t("settings_bio_hint")}
          <br />{t("settings_bio_example")}
        </p>
      </div>

      {/* Info rows */}
      <div className="border-t border-gray-100 dark:border-gray-700">
        <AccountInfoRow icon="fa-user" label={t("settings_name")} value={user} />
        {profile.phone && <AccountInfoRow icon="fa-phone" label={t("settings_phone")} value={profile.phone} />}
        <AccountInfoRow icon="fa-at" label={t("settings_username")} value={`@${user}`} />
      </div>

      <div className="px-4 py-2">
        <p className="text-xs text-gray-400 dark:text-gray-500">
          {t("settings_username_hint")}
        </p>
      </div>

      {/* Birthday */}
      <div className="border-t border-gray-100 dark:border-gray-700">
        <AccountInfoRow icon="fa-birthday-cake" label={t("settings_birthday")} value={profile.birthday || t("add")} isAction={!profile.birthday} />
      </div>

      <div className="px-4 py-2">
        <p className="text-xs text-gray-400 dark:text-gray-500">
          {t("settings_birthday_hint")}
        </p>
      </div>

      {/* Add Account */}
      <div className="border-t border-gray-100 dark:border-gray-700">
        <button
          onClick={() => { addAccount(); navigate(`/${lang}/login`); }}
          className="flex items-center gap-4 px-4 py-3 w-full hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors"
        >
          <i className="fas fa-plus-circle w-5 text-center text-blue-500" />
          <span className="text-sm text-blue-500 font-medium">{t("sidebar_add_account")}</span>
        </button>
      </div>
    </div>
  );
}

function AccountInfoRow({ icon, label, value, isAction }) {
  return (
    <div className="flex items-center gap-4 px-4 py-3 hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors cursor-pointer">
      <i className={`fas ${icon} w-5 text-center text-gray-400`} />
      <div className="flex-1 min-w-0">
        <div className="text-sm text-gray-900 dark:text-white">{label}</div>
      </div>
      <span className={`text-sm ${isAction ? "text-blue-500" : "text-blue-500"}`}>{value}</span>
    </div>
  );
}

function NotificationsSection() {
  const { t } = useLanguage();
  const [notifSound, setNotifSound] = useState(
    () => localStorage.getItem("app_notif_sound") !== "false"
  );
  const [messagePreview, setMessagePreview] = useState(
    () => localStorage.getItem("app_msg_preview") !== "false"
  );
  const [desktopNotif, setDesktopNotif] = useState(
    () => localStorage.getItem("app_desktop_notif") !== "false"
  );

  const save = (key, val) => {
    localStorage.setItem(key, val.toString());
  };

  return (
    <div className="space-y-1 divide-y divide-gray-100 dark:divide-gray-700">
      <SettingToggle
        label={t("settings_notif_sound")}
        description={t("settings_notif_sound_desc")}
        checked={notifSound}
        onChange={(v) => { setNotifSound(v); save("app_notif_sound", v); }}
      />
      <SettingToggle
        label={t("settings_msg_preview")}
        description={t("settings_msg_preview_desc")}
        checked={messagePreview}
        onChange={(v) => { setMessagePreview(v); save("app_msg_preview", v); }}
      />
      <SettingToggle
        label={t("settings_desktop_notif")}
        description={t("settings_desktop_notif_desc")}
        checked={desktopNotif}
        onChange={(v) => {
          setDesktopNotif(v);
          save("app_desktop_notif", v);
          if (v && Notification.permission === "default") {
            Notification.requestPermission();
          }
        }}
      />
    </div>
  );
}

function PrivacySection() {
  const { t } = useLanguage();
  const [lastSeen, setLastSeen] = useState(
    () => localStorage.getItem("app_last_seen") || "everyone"
  );
  const [profilePhoto, setProfilePhoto] = useState(
    () => localStorage.getItem("app_profile_photo_privacy") || "everyone"
  );
  const [blockedUsers, setBlockedUsers] = useState([]);
  const [loadingBlocked, setLoadingBlocked] = useState(false);

  useEffect(() => {
    loadBlockedUsers();
  }, []);

  const loadBlockedUsers = async () => {
    setLoadingBlocked(true);
    try {
      const list = await fetchJSON("/api/block");
      setBlockedUsers(list);
    } catch {
      setBlockedUsers([]);
    }
    setLoadingBlocked(false);
  };

  const handleUnblock = async (username) => {
    try {
      await fetchJSON(`/api/block/${username}`, { method: "DELETE" });
      setBlockedUsers((prev) => prev.filter((u) => u.username !== username));
    } catch (err) {
      console.error("Unblock error:", err);
    }
  };

  const save = (key, val) => localStorage.setItem(key, val);

  return (
    <div className="space-y-4">
      <div>
        <div className="text-sm font-medium text-gray-900 dark:text-white mb-2">{t("settings_last_seen")}</div>
        <select
          value={lastSeen}
          onChange={(e) => { setLastSeen(e.target.value); save("app_last_seen", e.target.value); }}
          className="w-full px-3 py-2.5 border border-gray-300 dark:border-gray-600 rounded-xl bg-white dark:bg-gray-800 text-sm text-gray-900 dark:text-white outline-none focus:ring-2 focus:ring-blue-500"
        >
          <option value="everyone">{t("settings_everyone")}</option>
          <option value="contacts">{t("settings_contacts_only")}</option>
          <option value="nobody">{t("settings_nobody")}</option>
        </select>
      </div>
      <div>
        <div className="text-sm font-medium text-gray-900 dark:text-white mb-2">{t("settings_profile_photo")}</div>
        <select
          value={profilePhoto}
          onChange={(e) => { setProfilePhoto(e.target.value); save("app_profile_photo_privacy", e.target.value); }}
          className="w-full px-3 py-2.5 border border-gray-300 dark:border-gray-600 rounded-xl bg-white dark:bg-gray-800 text-sm text-gray-900 dark:text-white outline-none focus:ring-2 focus:ring-blue-500"
        >
          <option value="everyone">{t("settings_everyone")}</option>
          <option value="contacts">{t("settings_contacts_only")}</option>
          <option value="nobody">{t("settings_nobody")}</option>
        </select>
      </div>

      {/* Blocked users */}
      <div className="border-t border-gray-100 dark:border-gray-700 pt-4">
        <div className="text-sm font-medium text-gray-900 dark:text-white mb-3">
          {t("settings_blocked_users")}
        </div>
        {loadingBlocked ? (
          <p className="text-xs text-gray-400 text-center py-4">{t("loading")}</p>
        ) : blockedUsers.length === 0 ? (
          <div className="text-center py-4">
            <i className="fas fa-check-circle text-2xl text-green-400 mb-2" />
            <p className="text-xs text-gray-400">{t("settings_no_blocked")}</p>
          </div>
        ) : (
          <div className="space-y-1 max-h-48 overflow-y-auto">
            {blockedUsers.map((u) => (
              <div
                key={u.username}
                className="flex items-center gap-3 px-3 py-2 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-800"
              >
                <Avatar src={u.avatar} name={u.username} size={36} />
                <span className="flex-1 text-sm font-medium text-gray-900 dark:text-white">{u.username}</span>
                <button
                  onClick={() => handleUnblock(u.username)}
                  className="px-3 py-1 text-xs bg-red-500 text-white rounded-full hover:bg-red-600 transition-colors"
                >
                  {t("chat_unblock")}
                </button>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function ChatSection({ settings }) {
  const { t } = useLanguage();
  const [messageSize, setMessageSize] = useState(settings.messageSize);
  const [sendByEnter, setSendByEnter] = useState(settings.sendByEnter);
  const [chatBg, setChatBg] = useState(settings.chatBg);

  return (
    <div className="space-y-4">
      <div>
        <div className="text-sm font-medium text-gray-900 dark:text-white mb-2">{t("settings_msg_size")}</div>
        <div className="flex items-center gap-3">
          <input
            type="range"
            min="12"
            max="24"
            value={messageSize}
            onChange={(e) => {
              const v = parseInt(e.target.value);
              setMessageSize(v);
              saveSetting(KEYS.MESSAGE_SIZE, v.toString());
            }}
            className="flex-1 h-1.5 bg-gray-200 dark:bg-gray-700 rounded-full appearance-none cursor-pointer accent-blue-500"
          />
          <span className="text-sm font-medium text-blue-500 w-8 text-right">{messageSize}px</span>
        </div>
      </div>

      <SettingToggle
        label={t("settings_send_enter")}
        description={t("settings_send_enter_desc")}
        checked={sendByEnter}
        onChange={(v) => { setSendByEnter(v); saveSetting(KEYS.SEND_BY_ENTER, v.toString()); }}
      />

      <div>
        <div className="text-sm font-medium text-gray-900 dark:text-white mb-2">{t("settings_chat_bg")}</div>
        <div className="grid grid-cols-4 gap-2">
          {["", "bg1", "bg2", "bg3", "bg4", "bg5", "bg6", "bg7"].map((bg) => (
            <button
              key={bg}
              onClick={() => { setChatBg(bg); saveSetting(KEYS.CHAT_BG, bg); }}
              className={`h-16 rounded-lg border-2 transition-colors ${
                chatBg === bg
                  ? "border-blue-500"
                  : "border-gray-200 dark:border-gray-700"
              } ${bg ? `bg-gradient-to-br ${getBgGradient(bg)}` : "bg-gray-100 dark:bg-gray-800"}`}
            >
              {!bg && <i className="fas fa-ban text-gray-400" />}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}

function getBgGradient(bg) {
  const gradients = {
    bg1: "from-blue-400 to-purple-500",
    bg2: "from-green-400 to-blue-500",
    bg3: "from-pink-400 to-red-500",
    bg4: "from-yellow-400 to-orange-500",
    bg5: "from-indigo-400 to-cyan-500",
    bg6: "from-teal-400 to-green-500",
    bg7: "from-gray-400 to-gray-600",
  };
  return gradients[bg] || "";
}

function FoldersSection() {
  const { t } = useLanguage();
  return (
    <div className="text-center py-8">
      <i className="fas fa-folder-open text-4xl text-gray-300 dark:text-gray-600 mb-3" />
      <p className="text-sm text-gray-500 dark:text-gray-400">{t("settings_folders_soon")}</p>
    </div>
  );
}

function AdvancedSection() {
  const { t } = useLanguage();
  const [autoDownload, setAutoDownload] = useState(
    () => localStorage.getItem("app_auto_download") !== "false"
  );
  const [autoPlayGif, setAutoPlayGif] = useState(
    () => localStorage.getItem("app_auto_play_gif") !== "false"
  );

  const save = (key, val) => localStorage.setItem(key, val.toString());

  return (
    <div className="space-y-1 divide-y divide-gray-100 dark:divide-gray-700">
      <SettingToggle
        label={t("settings_auto_download")}
        description={t("settings_auto_download_desc")}
        checked={autoDownload}
        onChange={(v) => { setAutoDownload(v); save("app_auto_download", v); }}
      />
      <SettingToggle
        label={t("settings_auto_gif")}
        description={t("settings_auto_gif_desc")}
        checked={autoPlayGif}
        onChange={(v) => { setAutoPlayGif(v); save("app_auto_play_gif", v); }}
      />
    </div>
  );
}

function SpeakersSection() {
  const { t } = useLanguage();
  const [speakerDevice, setSpeakerDevice] = useState("default");
  const [micDevice, setMicDevice] = useState("default");
  const [cameraDevice, setCameraDevice] = useState("default");
  const [devices, setDevices] = useState({ audio: [], video: [], mic: [] });

  useState(() => {
    if (navigator.mediaDevices?.enumerateDevices) {
      navigator.mediaDevices.enumerateDevices().then((list) => {
        setDevices({
          audio: list.filter((d) => d.kind === "audiooutput"),
          mic: list.filter((d) => d.kind === "audioinput"),
          video: list.filter((d) => d.kind === "videoinput"),
        });
      }).catch(() => {});
    }
  });

  const selectClass = "w-full px-3 py-2.5 border border-gray-300 dark:border-gray-600 rounded-xl bg-white dark:bg-gray-800 text-sm text-gray-900 dark:text-white outline-none focus:ring-2 focus:ring-blue-500";

  return (
    <div className="space-y-4">
      <div>
        <div className="text-sm font-medium text-gray-900 dark:text-white mb-2">{t("settings_speaker")}</div>
        <select value={speakerDevice} onChange={(e) => setSpeakerDevice(e.target.value)} className={selectClass}>
          <option value="default">{t("settings_default_device")}</option>
          {devices.audio.map((d) => (
            <option key={d.deviceId} value={d.deviceId}>{d.label || t("settings_speaker")}</option>
          ))}
        </select>
      </div>
      <div>
        <div className="text-sm font-medium text-gray-900 dark:text-white mb-2">{t("settings_mic")}</div>
        <select value={micDevice} onChange={(e) => setMicDevice(e.target.value)} className={selectClass}>
          <option value="default">{t("settings_default_device")}</option>
          {devices.mic.map((d) => (
            <option key={d.deviceId} value={d.deviceId}>{d.label || t("settings_mic")}</option>
          ))}
        </select>
      </div>
      <div>
        <div className="text-sm font-medium text-gray-900 dark:text-white mb-2">{t("settings_camera")}</div>
        <select value={cameraDevice} onChange={(e) => setCameraDevice(e.target.value)} className={selectClass}>
          <option value="default">{t("settings_default_device")}</option>
          {devices.video.map((d) => (
            <option key={d.deviceId} value={d.deviceId}>{d.label || t("settings_camera")}</option>
          ))}
        </select>
      </div>
    </div>
  );
}

function BatterySection() {
  const { t } = useLanguage();
  const [reducedMotion, setReducedMotion] = useState(
    () => localStorage.getItem("app_reduced_motion") === "true"
  );
  const [powerSaver, setPowerSaver] = useState(
    () => localStorage.getItem("app_power_saver") === "true"
  );

  const save = (key, val) => localStorage.setItem(key, val.toString());

  return (
    <div className="space-y-1 divide-y divide-gray-100 dark:divide-gray-700">
      <SettingToggle
        label={t("settings_reduce_motion")}
        description={t("settings_reduce_motion_desc")}
        checked={reducedMotion}
        onChange={(v) => {
          setReducedMotion(v);
          save("app_reduced_motion", v);
          document.documentElement.classList.toggle("reduce-motion", v);
        }}
      />
      <SettingToggle
        label={t("settings_power_saver")}
        description={t("settings_power_saver_desc")}
        checked={powerSaver}
        onChange={(v) => { setPowerSaver(v); save("app_power_saver", v); }}
      />
    </div>
  );
}

function LanguageSection() {
  const { lang: currentLang, changeLanguage, t } = useLanguage();
  const navigate = useNavigate();
  const [showTranslate, setShowTranslate] = useState(
    () => localStorage.getItem("app_show_translate") === "true"
  );
  const [translateChats, setTranslateChats] = useState(
    () => localStorage.getItem("app_translate_chats") === "true"
  );
  const [search, setSearch] = useState("");

  const languages = [
    { code: "uz", label: "O'zbek", sub: "O'zbek" },
    { code: "en", label: "English", sub: "English" },
    { code: "ru", label: "Русский", sub: "Russian" },
    { code: "tr", label: "Türkçe", sub: "Turkish" },
    { code: "de", label: "Deutsch", sub: "German" },
    { code: "fr", label: "Français", sub: "French" },
    { code: "es", label: "Español", sub: "Spanish" },
    { code: "ar", label: "العربية", sub: "Arabic" },
    { code: "zh", label: "中文", sub: "Chinese" },
    { code: "ja", label: "日本語", sub: "Japanese" },
    { code: "ko", label: "한국어", sub: "Korean" },
  ];

  const filtered = search
    ? languages.filter((l) =>
        l.label.toLowerCase().includes(search.toLowerCase()) ||
        l.sub.toLowerCase().includes(search.toLowerCase())
      )
    : languages;

  const save = (key, val) => localStorage.setItem(key, val.toString());

  return (
    <div>
      {/* Toggles */}
      <div className="px-1">
        <SettingToggle
          label={t("settings_show_translate")}
          description=""
          checked={showTranslate}
          onChange={(v) => { setShowTranslate(v); save("app_show_translate", v); }}
        />
        <SettingToggle
          label={t("settings_translate_chats")}
          description=""
          checked={translateChats}
          onChange={(v) => { setTranslateChats(v); save("app_translate_chats", v); }}
        />
      </div>

      <p className="text-xs text-gray-400 dark:text-gray-500 px-1 pb-3">
        {t("settings_translate_hint")}
      </p>

      <div className="border-t border-gray-100 dark:border-gray-700" />

      {/* Search */}
      <div className="flex items-center gap-2 px-3 py-2.5">
        <i className="fas fa-search text-gray-400 text-sm" />
        <input
          type="text"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder={t("search")}
          className="flex-1 text-sm text-gray-900 dark:text-white bg-transparent outline-none placeholder-gray-400"
        />
      </div>

      <div className="border-t border-gray-100 dark:border-gray-700" />

      {/* Language list */}
      <div className="max-h-64 overflow-y-auto">
        {filtered.map((lang) => (
          <button
            key={lang.code}
            onClick={() => {
              changeLanguage(lang.code);
              navigate(`/${lang.code}`);
            }}
            className={`w-full flex items-center gap-3 px-4 py-2.5 transition-colors ${
              currentLang === lang.code
                ? "bg-blue-50 dark:bg-blue-900/20"
                : "hover:bg-gray-50 dark:hover:bg-gray-800"
            }`}
          >
            <div className={`w-5 h-5 rounded-full border-2 flex items-center justify-center ${
              currentLang === lang.code
                ? "border-blue-500 bg-blue-500"
                : "border-gray-300 dark:border-gray-600"
            }`}>
              {currentLang === lang.code && (
                <div className="w-2 h-2 rounded-full bg-white" />
              )}
            </div>
            <div className="text-left flex-1">
              <div className={`text-sm font-medium ${
                currentLang === lang.code ? "text-blue-600" : "text-gray-900 dark:text-white"
              }`}>{lang.label}</div>
              <div className="text-xs text-gray-400">{lang.sub}</div>
            </div>
          </button>
        ))}
      </div>

      {/* OK button */}
      <div className="border-t border-gray-100 dark:border-gray-700 px-4 py-3 flex justify-end">
        <span className="text-sm font-medium text-blue-500 cursor-pointer hover:text-blue-600">{t("ok")}</span>
      </div>
    </div>
  );
}
