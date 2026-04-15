import { useState, useRef, useEffect } from "react";
import Avatar from "@/components/common/Avatar";
import { useLanguage } from "@/context/LanguageContext";
import { formatLastActive } from "@/utils/formatters";

export default function ChatHeader({ chat, isOnline, lastActive, onBack, onInfo, onCall, onVideoCall, onSearch, onMute, isMuted, onClearHistory, onDeleteChat }) {
  const { t } = useLanguage();
  const [searchOpen, setSearchOpen] = useState(false);
  const [searchQuery, setSearchQuery] = useState("");
  const [menuOpen, setMenuOpen] = useState(false);
  const menuRef = useRef(null);

  const isGroup = chat.type === "group";
  const isChannel = chat.type === "channel";
  const isSaved = chat.username === "__SAVED_MESSAGES__";
  const name = isSaved ? t("chat_saved_messages") : isGroup || isChannel ? chat.name : (chat.full_name || chat.username);

  const statusText = isSaved
    ? ""
    : isGroup
      ? `${chat.memberCount || 0} ${t("chat_members")}`
      : isChannel
        ? `${chat.subscriberCount || 0} ${t("chat_subscribers")}`
        : isOnline
          ? t("online")
          : lastActive
            ? formatLastActive(lastActive)
            : t("offline");

  // Close menu on outside click
  useEffect(() => {
    if (!menuOpen) return;
    const handleClick = (e) => {
      if (menuRef.current && !menuRef.current.contains(e.target)) {
        setMenuOpen(false);
      }
    };
    const handleEsc = (e) => {
      if (e.key === "Escape") setMenuOpen(false);
    };
    window.addEventListener("mousedown", handleClick);
    window.addEventListener("keydown", handleEsc);
    return () => {
      window.removeEventListener("mousedown", handleClick);
      window.removeEventListener("keydown", handleEsc);
    };
  }, [menuOpen]);

  const handleSearchToggle = () => {
    if (searchOpen) {
      setSearchOpen(false);
      setSearchQuery("");
      onSearch?.("");
    } else {
      setSearchOpen(true);
    }
  };

  const handleSearchChange = (e) => {
    const q = e.target.value;
    setSearchQuery(q);
    onSearch?.(q);
  };

  const handleSearchKeyDown = (e) => {
    if (e.key === "Escape") {
      handleSearchToggle();
    }
  };

  // Build menu items based on chat type
  const getMenuItems = () => {
    if (isGroup) {
      return [
        { id: "mute", label: isMuted ? t("chat_unmute") : t("chat_mute"), icon: isMuted ? "fa-volume-up" : "fa-volume-mute", onClick: () => onMute?.() },
        { id: "info", label: t("group_info"), icon: "fa-info-circle", onClick: () => onInfo?.() },
        { id: "export", label: t("chat_export_history"), icon: "fa-file-export", onClick: () => {} },
        { id: "report", label: t("chat_report"), icon: "fa-flag", onClick: () => {} },
        { id: "leave", label: t("group_leave"), icon: "fa-sign-out-alt", danger: true, dividerTop: true, onClick: () => onDeleteChat?.() },
      ];
    }

    if (isChannel) {
      return [
        { id: "mute", label: isMuted ? t("chat_unmute") : t("chat_mute"), icon: isMuted ? "fa-volume-up" : "fa-volume-mute", onClick: () => onMute?.() },
        { id: "info", label: t("channel_info"), icon: "fa-info-circle", onClick: () => onInfo?.() },
        { id: "manage", label: t("channel_manage"), icon: "fa-sliders-h", onClick: () => onInfo?.() },
        { id: "poll", label: t("channel_poll"), icon: "fa-poll", onClick: () => {} },
        { id: "export", label: t("chat_export_history"), icon: "fa-file-export", onClick: () => {} },
        { id: "clear", label: t("chat_clear_history"), icon: "fa-broom", onClick: () => onClearHistory?.() },
        { id: "leave", label: t("channel_leave"), icon: "fa-sign-out-alt", danger: true, dividerTop: true, onClick: () => onDeleteChat?.() },
      ];
    }

    if (isSaved) {
      return [
        { id: "export", label: t("chat_export_history"), icon: "fa-file-export", onClick: () => {} },
        { id: "clear", label: t("chat_clear_history"), icon: "fa-broom", onClick: () => onClearHistory?.() },
        { id: "delete", label: t("chat_delete_chat"), icon: "fa-trash", danger: true, dividerTop: true, onClick: () => onDeleteChat?.() },
      ];
    }

    // User DM
    return [
      { id: "mute", label: isMuted ? t("chat_unmute") : t("chat_mute"), icon: isMuted ? "fa-volume-up" : "fa-volume-mute", onClick: () => onMute?.() },
      { id: "info", label: t("modal_view_profile"), icon: "fa-user", onClick: () => onInfo?.() },
      { id: "export", label: t("chat_export_history"), icon: "fa-file-export", onClick: () => {} },
      { id: "clear", label: t("chat_clear_history"), icon: "fa-broom", onClick: () => onClearHistory?.() },
      { id: "delete", label: t("chat_delete_chat"), icon: "fa-trash", danger: true, dividerTop: true, onClick: () => onDeleteChat?.() },
    ];
  };

  const menuItems = getMenuItems();

  // Search mode
  if (searchOpen) {
    return (
      <div className="flex flex-col bg-white dark:bg-[#242f3d] shrink-0 border-b border-gray-200 dark:border-gray-700">
        <div className="flex items-center gap-2 px-3 py-2">
          <button
            onClick={handleSearchToggle}
            className="w-10 h-10 flex items-center justify-center text-gray-500 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-full"
          >
            <i className="fas fa-arrow-left" />
          </button>
          <input
            type="text"
            value={searchQuery}
            onChange={handleSearchChange}
            onKeyDown={handleSearchKeyDown}
            placeholder={t("contacts_search")}
            autoFocus
            className="flex-1 px-3 py-2 bg-transparent text-gray-900 dark:text-white outline-none text-[15px] placeholder-gray-400"
          />
          {searchQuery && (
            <button
              onClick={() => { setSearchQuery(""); onSearch?.(""); }}
              className="w-10 h-10 flex items-center justify-center text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 rounded-full"
            >
              <i className="fas fa-times" />
            </button>
          )}
        </div>
        <div className="flex items-center gap-2 px-4 py-1.5 border-t border-gray-100 dark:border-gray-700">
          <Avatar src={chat.avatar} name={chat.username || chat.name} size={28} />
          <span className="text-sm text-gray-500 dark:text-gray-400">{t("chat_search_in_chat")}</span>
          <button
            onClick={handleSearchToggle}
            className="ml-auto text-gray-400 hover:text-gray-600"
          >
            <i className="fas fa-times text-sm" />
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="flex items-center gap-3 px-4 py-1.5 bg-white dark:bg-[#242f3d] border-b border-gray-200 dark:border-gray-700 shrink-0">
      {/* Back button (mobile) */}
      <button
        onClick={onBack}
        className="p-2 text-gray-500 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-white/10 rounded-full md:hidden"
      >
        <i className="fas fa-arrow-left text-lg" />
      </button>

      {/* Avatar */}
      {isSaved ? (
        <div className="w-10 h-10 rounded-full bg-[#6c9fd2] flex items-center justify-center shrink-0">
          <i className="fas fa-bookmark text-white" />
        </div>
      ) : isGroup ? (
        <div className="w-10 h-10 rounded-full bg-[#63b16e] flex items-center justify-center shrink-0">
          {chat.avatar ? (
            <img src={chat.avatar} alt={name} className="w-10 h-10 rounded-full object-cover" />
          ) : (
            <i className="fas fa-users text-white" />
          )}
        </div>
      ) : isChannel ? (
        <div className="w-10 h-10 rounded-full bg-[#7b72c7] flex items-center justify-center shrink-0">
          {chat.avatar ? (
            <img src={chat.avatar} alt={name} className="w-10 h-10 rounded-full object-cover" />
          ) : (
            <i className="fas fa-bullhorn text-white" />
          )}
        </div>
      ) : (
        <Avatar src={chat.avatar} name={chat.username} size={40} online={isOnline} />
      )}

      {/* Name + status */}
      <div className="flex-1 min-w-0">
        <h3 className="font-semibold text-gray-900 dark:text-white text-[15px] truncate">{name}</h3>
        {statusText && (
          <p className={`text-xs truncate ${isOnline && !isGroup && !isChannel ? "text-[#3390ec]" : "text-gray-500 dark:text-gray-400"}`}>
            {statusText}
          </p>
        )}
      </div>

      {/* Action buttons */}
      <div className="flex items-center gap-0.5 shrink-0 min-w-max">
        {/* Search */}
        <button
          onClick={handleSearchToggle}
          className="w-10 h-10 flex items-center justify-center text-gray-500 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-white/10 active:scale-90 rounded-full transition-all cursor-pointer"
          title="Qidirish"
        >
          <i className="fas fa-search text-[15px]" />
        </button>

        {/* Audio call — only for user DMs */}
        {!isSaved && !isChannel && !isGroup && onCall && (
          <button
            onClick={onCall}
            className="w-10 h-10 flex items-center justify-center text-gray-500 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-white/10 active:scale-90 rounded-full transition-all cursor-pointer"
            title="Audio qo'ng'iroq"
          >
            <i className="fas fa-phone text-[15px]" />
          </button>
        )}

        {/* Video call — only for user DMs */}
        {!isSaved && !isChannel && !isGroup && onVideoCall && (
          <button
            onClick={onVideoCall}
            className="w-10 h-10 flex items-center justify-center text-gray-500 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-white/10 active:scale-90 rounded-full transition-all cursor-pointer"
            title="Video qo'ng'iroq"
          >
            <i className="fas fa-video text-[15px]" />
          </button>
        )}

        {/* Info panel toggle */}
        <button
          onClick={onInfo}
          className="w-10 h-10 flex items-center justify-center text-gray-500 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-white/10 active:scale-90 rounded-full transition-all cursor-pointer"
          title="Ma'lumot"
        >
          <i className="far fa-window-restore text-[15px]" />
        </button>

        {/* Three-dot menu — all chat types */}
        <div className="relative" ref={menuRef}>
          <button
            onClick={() => setMenuOpen(!menuOpen)}
            className="w-10 h-10 flex items-center justify-center text-gray-500 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-white/10 active:scale-90 rounded-full transition-all cursor-pointer"
          >
            <i className="fas fa-ellipsis-v text-[15px]" />
          </button>

          {menuOpen && (
            <div className="absolute right-0 top-full mt-1 min-w-56 rounded-xl bg-white dark:bg-[#2c2c2c] shadow-2xl border border-gray-200 dark:border-gray-700 py-1 z-50">
              {menuItems.map((item) => (
                <button
                  key={item.id}
                  type="button"
                  onClick={() => {
                    item.onClick?.();
                    setMenuOpen(false);
                  }}
                  className={`w-full flex items-center gap-3 px-4 py-2.5 text-left transition-colors ${
                    item.danger
                      ? "text-red-500 hover:bg-red-50 dark:hover:bg-red-900/20"
                      : "text-gray-900 dark:text-white hover:bg-gray-100 dark:hover:bg-white/10"
                  } ${item.dividerTop ? "border-t border-gray-200 dark:border-gray-700 mt-1 pt-3" : ""}`}
                >
                  <i className={`fas ${item.icon} w-5 text-center ${item.danger ? "text-red-500" : "text-gray-500 dark:text-gray-300"}`} />
                  <span className="text-[15px]">{item.label}</span>
                </button>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
