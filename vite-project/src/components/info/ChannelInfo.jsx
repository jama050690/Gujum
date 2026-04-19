import { useState, useEffect } from "react";
import { useAuth } from "@/context/AuthContext";
import { useLanguage } from "@/context/LanguageContext";
import { fetchJSON } from "@/utils/api";
import SharedMedia from "./SharedMedia";

export default function ChannelInfo({ channel, onDelete }) {
  const { user } = useAuth();
  const { t } = useLanguage();
  const [subscribers, setSubscribers] = useState([]);

  useEffect(() => {
    loadSubscribers();
  }, [channel.id]);

  const loadSubscribers = async () => {
    try {
      const data = await fetchJSON(`/api/channels/${channel.id}/subscribers`);
      setSubscribers(data);
    } catch (err) {
      console.error("Obunachillarni yuklashda xato:", err);
    }
  };

  const handleLeave = async () => {
    if (!confirm("Kanaldan chiqishni xohlaysizmi?")) return;
    try {
      await fetchJSON(`/api/channels/${channel.id}`, {
        method: "DELETE",
        body: JSON.stringify({ username: user }),
      });
      onDelete?.();
    } catch (err) {
      alert(err.message || "Kanaldan chiqishda xato");
    }
  };

  return (
    <div>
      {/* Channel avatar + name */}
      <div className="flex flex-col items-center text-center pt-6 pb-4 px-4">
        <div className="w-20 h-20 rounded-full bg-purple-500 flex items-center justify-center">
          {channel.avatar ? (
            <img src={channel.avatar} alt={channel.name} className="w-20 h-20 rounded-full object-cover" />
          ) : (
            <i className="fas fa-bullhorn text-white text-3xl" />
          )}
        </div>
        <h3 className="text-xl font-bold text-gray-900 dark:text-white mt-3">{channel.name}</h3>
        <p className="text-sm text-gray-400">{subscribers.length} {t("chat_subscribers")}</p>
      </div>

      {/* Quick actions */}
      <div className="flex justify-center gap-6 pb-4 px-4">
        <QuickAction icon="fa-bell" label={t("chat_mute_short")} />
        <QuickAction icon="fa-comment" label={t("chat_message")} />
        <QuickAction icon="fa-gift" label={t("chat_gift")} />
      </div>

      {/* Description */}
      {channel.description && (
        <div className="border-t border-gray-200 dark:border-gray-700 py-3 px-4">
          <p className="text-sm text-gray-900 dark:text-white whitespace-pre-wrap">{channel.description}</p>
          <p className="text-xs text-gray-400 mt-1">{t("channel_desc")}</p>
        </div>
      )}

      {/* Shared Media */}
      <div className="px-2">
        <SharedMedia />
      </div>

      {/* Bottom actions */}
      <div className="border-t border-gray-200 dark:border-gray-700 mt-2 py-1">
        <BottomAction icon="fa-sign-out-alt" label={t("channel_leave")} onClick={handleLeave} />
        <BottomAction icon="fa-exclamation-circle" label={t("chat_report")} danger />
      </div>
    </div>
  );
}

function QuickAction({ icon, label, onClick }) {
  return (
    <button
      onClick={onClick}
      className="flex flex-col items-center gap-1.5 min-w-18 py-2 px-3 rounded-xl border border-gray-200 dark:border-gray-700 hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors"
    >
      <i className={`fas ${icon} text-[#419fd9]`} />
      <span className="text-xs text-gray-600 dark:text-gray-400">{label}</span>
    </button>
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
