import { useState } from "react";
import { useAuth } from "@/context/AuthContext";
import { useSocket } from "@/context/SocketContext";
import { useLanguage } from "@/context/LanguageContext";
import { fetchJSON } from "@/utils/api";
import Avatar from "@/components/common/Avatar";
import Modal from "./Modal";

export default function AddFriendModal({ isOpen, onClose }) {
  const { user, avatar } = useAuth();
  const { socket } = useSocket();
  const { t } = useLanguage();
  const [search, setSearch] = useState("");
  const [results, setResults] = useState([]);
  const [statuses, setStatuses] = useState({});
  const [loading, setLoading] = useState(false);

  const handleSearch = async () => {
    if (!search.trim()) return;
    setLoading(true);
    try {
      const data = await fetchJSON(`/api/users/search?q=${encodeURIComponent(search)}`);
      const filtered = data.filter((u) => u.username !== user);
      setResults(filtered);

      // Har bir user bilan do'stlik statusini tekshir
      const statusMap = {};
      await Promise.all(
        filtered.map(async (u) => {
          try {
            const res = await fetchJSON(`/api/friends/status/${u.username}`);
            statusMap[u.username] = res;
          } catch {
            statusMap[u.username] = { status: "none" };
          }
        })
      );
      setStatuses(statusMap);
    } catch (err) {
      console.error("Qidirishda xato:", err);
    }
    setLoading(false);
  };

  const handleSendRequest = async (targetUsername) => {
    try {
      await fetchJSON("/api/friends/request", {
        method: "POST",
        body: JSON.stringify({ targetUsername }),
      });
      setStatuses((prev) => ({ ...prev, [targetUsername]: { status: "sent" } }));

      // Real-time notification
      if (socket) {
        socket.emit("FRIEND_REQUEST", {
          targetUsername,
          senderUsername: user,
          senderAvatar: avatar,
        });
      }
    } catch (err) {
      alert(err.message || "So'rov yuborishda xato");
    }
  };

  const getStatusButton = (username) => {
    const s = statuses[username];
    if (!s) return null;

    switch (s.status) {
      case "friends":
        return (
          <span className="px-3 py-1 text-xs bg-green-100 dark:bg-green-900/30 text-green-600 dark:text-green-400 rounded-full">
            {t("friend_status_friend")}
          </span>
        );
      case "sent":
        return (
          <span className="px-3 py-1 text-xs bg-yellow-100 dark:bg-yellow-900/30 text-yellow-600 dark:text-yellow-400 rounded-full">
            {t("friend_status_sent")}
          </span>
        );
      case "received":
        return (
          <span className="px-3 py-1 text-xs bg-blue-100 dark:bg-blue-900/30 text-blue-600 dark:text-blue-400 rounded-full">
            {t("friend_status_received")}
          </span>
        );
      default:
        return (
          <button
            onClick={() => handleSendRequest(username)}
            className="px-3 py-1 text-xs bg-blue-500 text-white rounded-full hover:bg-blue-600 transition-colors"
          >
            {t("friend_add_button")}
          </button>
        );
    }
  };

  return (
    <Modal isOpen={isOpen} onClose={onClose} title={t("friend_add")}>
      <div className="p-4">
        {/* Search */}
        <div className="flex gap-2 mb-4">
          <div className="flex-1 relative">
            <i className="fas fa-search absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 text-sm" />
            <input
              type="text"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && handleSearch()}
              placeholder={t("friend_search_placeholder")}
              className="w-full pl-9 pr-4 py-2.5 bg-gray-100 dark:bg-gray-800 rounded-xl text-sm outline-none dark:text-white"
            />
          </div>
          <button
            onClick={handleSearch}
            disabled={loading}
            className="px-4 py-2 bg-blue-500 text-white rounded-xl text-sm font-medium hover:bg-blue-600 transition-colors disabled:opacity-50"
          >
            {loading ? "..." : t("friend_search_button")}
          </button>
        </div>

        {/* Results */}
        <div className="max-h-80 overflow-y-auto space-y-1">
          {results.length === 0 && !loading && (
            <div className="text-center py-8">
              <i className="fas fa-user-plus text-3xl text-gray-300 dark:text-gray-600 mb-3" />
              <p className="text-sm text-gray-400">{t("friend_search_hint")}</p>
            </div>
          )}
          {results.map((u) => (
            <div
              key={u.username}
              className="flex items-center gap-3 p-2.5 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-800"
            >
              <Avatar src={u.avatar} name={u.username} size={40} />
              <span className="flex-1 text-sm font-medium text-gray-900 dark:text-white">
                {u.username}
              </span>
              {getStatusButton(u.username)}
            </div>
          ))}
        </div>
      </div>
    </Modal>
  );
}
