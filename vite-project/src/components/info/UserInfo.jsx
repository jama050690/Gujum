import { useState, useEffect } from "react";
import Avatar from "@/components/common/Avatar";
import { useLanguage } from "@/context/LanguageContext";
import { formatLastActive } from "@/utils/formatters";
import { fetchJSON } from "@/utils/api";
import SharedMedia from "./SharedMedia";

export default function UserInfo({ user, isOnline, onDeleteChat }) {
  const { t } = useLanguage();
  const [isBlocked, setIsBlocked] = useState(false);
  const [loading, setLoading] = useState(false);
  const [profile, setProfile] = useState(null);

  useEffect(() => {
    checkBlocked();
    fetchProfile();
  }, [user.username]);

  const fetchProfile = async () => {
    if (!user.username) return;
    try {
      const data = await fetchJSON(`/api/users/profile/${user.username}`);
      setProfile(data);
    } catch {
      setProfile(null);
    }
  };

  const checkBlocked = async () => {
    try {
      const list = await fetchJSON("/api/block");
      setIsBlocked(list.some((b) => b.username === user.username));
    } catch {
      setIsBlocked(false);
    }
  };

  const handleBlock = async () => {
    if (loading) return;
    setLoading(true);
    try {
      if (isBlocked) {
        await fetchJSON(`/api/block/${user.username}`, { method: "DELETE" });
        setIsBlocked(false);
      } else {
        await fetchJSON("/api/block", {
          method: "POST",
          body: JSON.stringify({ targetUsername: user.username }),
        });
        setIsBlocked(true);
      }
    } catch (err) {
      console.error("Bloklashda xato:", err);
    }
    setLoading(false);
  };

  const handleSpam = async () => {
    if (loading) return;
    const reason = prompt(t("block_spam_reason"));
    if (reason === null) return;
    setLoading(true);
    try {
      await fetchJSON("/api/spam/report", {
        method: "POST",
        body: JSON.stringify({ targetUsername: user.username, reason }),
      });
      setIsBlocked(true);
      alert(t("block_spam_done"));
    } catch (err) {
      console.error("Spam reportda xato:", err);
    }
    setLoading(false);
  };

  const handleDeleteChat = async () => {
    if (!confirm(`${user.username} bilan chat tarixini o'chirishni xohlaysizmi?`)) return;
    try {
      await fetchJSON(`/api/users/chat/${user.username}`, { method: "DELETE" });
      onDeleteChat?.(user.username);
    } catch (err) {
      console.error("Chatni o'chirishda xato:", err);
    }
  };

  return (
    <div>
      {/* Avatar + Name */}
      <div className="flex flex-col items-center text-center pt-6 pb-4 px-4">
        <Avatar src={user.avatar} name={user.username} size={80} online={isOnline} />
        <h3 className="text-xl font-bold text-gray-900 dark:text-white mt-3">{profile?.full_name || user.full_name || user.username}</h3>
        <p className={`text-sm ${isOnline ? "text-green-500" : "text-gray-400"}`}>
          {isOnline ? t("online") : user.lastActive ? `${t("chat_last_seen")}: ${formatLastActive(user.lastActive)}` : t("offline")}
        </p>
        {isBlocked && (
          <span className="mt-1 text-xs text-red-500 bg-red-50 dark:bg-red-900/20 px-2 py-0.5 rounded-full">
            {t("chat_blocked")}
          </span>
        )}
      </div>

      {/* Quick actions */}
      <div className="flex justify-center gap-6 pb-4 px-4">
        <QuickAction icon="fa-comment" label={t("chat_message")} />
        <QuickAction icon="fa-volume-mute" label={t("chat_mute_short")} />
        <QuickAction icon="fa-gift" label={t("chat_gift")} />
      </div>

      {/* Info items */}
      <div className="border-t border-gray-200 dark:border-gray-700 py-3 px-4 space-y-3">
        {(profile?.phone || user.phone) && (
          <InfoItem icon="fa-phone" label={t("settings_phone")} value={profile?.phone || user.phone} />
        )}
        <InfoItem icon="fa-at" label={t("settings_username")} value={`@${user.username}`} />
        {(profile?.bio || user.bio) && (
          <InfoItem icon="fa-info-circle" label={t("settings_bio")} value={profile?.bio || user.bio} />
        )}
      </div>

      {/* Shared Media */}
      <div className="px-2">
        <SharedMedia />
      </div>

      {/* Bottom actions */}
      <div className="border-t border-gray-200 dark:border-gray-700 mt-2 py-1">
        <BottomAction icon="fa-pen" label={t("chat_edit_contact")} />
        <BottomAction
          icon={isBlocked ? "fa-unlock" : "fa-ban"}
          label={isBlocked ? t("chat_unblock") : t("chat_block")}
          danger
          onClick={handleBlock}
        />
        <BottomAction icon="fa-shield-halved" label={t("block_mark_spam")} danger onClick={handleSpam} />
        <BottomAction icon="fa-trash" label={t("chat_delete_chat")} danger onClick={handleDeleteChat} />
      </div>
    </div>
  );
}

function QuickAction({ icon, label, onClick }) {
  return (
    <button
      onClick={onClick}
      className="flex flex-col items-center gap-1.5 min-w-[72px] py-2 px-3 rounded-xl border border-gray-200 dark:border-gray-700 hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors"
    >
      <i className={`fas ${icon} text-[#419fd9]`} />
      <span className="text-xs text-gray-600 dark:text-gray-400">{label}</span>
    </button>
  );
}

function InfoItem({ icon, label, value }) {
  return (
    <div className="flex items-center gap-3">
      <div className="w-9 h-9 rounded-full bg-blue-50 dark:bg-blue-900/30 flex items-center justify-center shrink-0">
        <i className={`fas ${icon} text-blue-500 text-sm`} />
      </div>
      <div>
        <p className="text-sm text-gray-900 dark:text-white">{value}</p>
        <p className="text-xs text-gray-400">{label}</p>
      </div>
    </div>
  );
}

function BottomAction({ icon, label, danger, onClick }) {
  return (
    <button
      onClick={onClick}
      className={`w-full flex items-center gap-3 px-4 py-3 text-left transition-colors hover:bg-gray-50 dark:hover:bg-gray-800 ${
        danger ? "text-red-500" : "text-gray-700 dark:text-gray-300"
      }`}
    >
      <i className={`fas ${icon} w-5 text-center ${danger ? "text-red-500" : "text-gray-400"}`} />
      <span className="text-[15px]">{label}</span>
    </button>
  );
}
