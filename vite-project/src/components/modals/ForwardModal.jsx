import { useState, useEffect, useMemo } from "react";
import { useAuth } from "@/context/AuthContext";
import { useChat } from "@/context/ChatContext";
import { useLanguage } from "@/context/LanguageContext";
import Modal from "./Modal";
import Avatar from "@/components/common/Avatar";

export default function ForwardModal({ isOpen, onClose, message, onForward }) {
  const { user } = useAuth();
  const { users, onlineUsers } = useChat();
  const { t } = useLanguage();
  const [search, setSearch] = useState("");
  const [sending, setSending] = useState(null);

  useEffect(() => {
    if (!isOpen || !user) return;
    setSearch("");
    setSending(null);
  }, [isOpen, user]);

  const allChats = useMemo(() => {
    const list = [];

    // Direct users (exclude self and saved messages)
    users.forEach((u) => {
      if (u.username && u.username !== user && u.username !== "__SAVED_MESSAGES__") {
        list.push({
          key: `user-${u.username}`,
          type: "user",
          username: u.username,
          name: u.full_name || u.username,
          avatar: u.avatar,
          online: onlineUsers.has(u.username),
        });
      }
    });

    return list;
  }, [users, user, onlineUsers]);

  const filtered = useMemo(() => {
    if (!search.trim()) return allChats;
    const q = search.toLowerCase();
    return allChats.filter((c) => c.name.toLowerCase().includes(q) || c.username?.toLowerCase().includes(q));
  }, [allChats, search]);

  const handleSelect = async (chat) => {
    if (sending) return;
    setSending(chat.key);
    try {
      await onForward?.(message, chat);
      onClose();
    } catch (err) {
      console.error("Forward xato:", err);
    }
    setSending(null);
  };

  return (
    <Modal isOpen={isOpen} onClose={onClose} title={t("forward_title") || "Xabarni uzatish"}>
      <div className="p-3">
        <input
          type="text"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder={t("contacts_search") || "Qidirish..."}
          className="w-full px-4 py-2.5 bg-gray-100 dark:bg-gray-800 rounded-xl outline-none text-sm text-gray-900 dark:text-white placeholder-gray-400 mb-2"
          autoFocus
        />
      </div>

      {/* Message preview */}
      <div className="mx-3 mb-2 px-3 py-2 bg-gray-50 dark:bg-gray-800/50 rounded-lg border border-gray-200 dark:border-gray-700">
        <p className="text-xs text-gray-400 mb-0.5">{message?.username}</p>
        {message?.content && (
          <p className="text-sm text-gray-700 dark:text-gray-300 truncate">{message.content}</p>
        )}
        {message?.image && !message?.content && (
          <p className="text-sm text-gray-400 italic">Rasm</p>
        )}
        {message?.audio && !message?.content && !message?.image && (
          <p className="text-sm text-gray-400 italic">Ovozli xabar</p>
        )}
      </div>

      <div className="px-1 pb-3">
        {filtered.length === 0 && (
          <p className="text-center text-sm text-gray-400 py-6">{t("chat_nothing_found") || "Hech narsa topilmadi"}</p>
        )}

        {filtered.map((chat) => (
          <button
            key={chat.key}
            onClick={() => handleSelect(chat)}
            disabled={sending === chat.key}
            className="w-full flex items-center gap-3 px-4 py-2.5 hover:bg-gray-100 dark:hover:bg-gray-800 rounded-xl transition-colors text-left"
          >
            <Avatar src={chat.avatar} name={chat.username} size={40} online={chat.online} />

            <div className="flex-1 min-w-0">
              <p className="text-[15px] font-medium text-gray-900 dark:text-white truncate">{chat.name}</p>
              <p className="text-xs text-gray-400 truncate">
                {chat.online ? t("online") : ""}
              </p>
            </div>

            {sending === chat.key && (
              <i className="fas fa-spinner fa-spin text-[#419fd9]" />
            )}
          </button>
        ))}
      </div>
    </Modal>
  );
}
