import { useState, useEffect } from "react";
import { useAuth } from "@/context/AuthContext";
import { useSocket } from "@/context/SocketContext";
import { useLanguage } from "@/context/LanguageContext";
import { fetchJSON } from "@/utils/api";
import Avatar from "@/components/common/Avatar";
import Modal from "./Modal";

export default function FriendRequestsModal({ isOpen, onClose }) {
  const { user, avatar } = useAuth();
  const { socket } = useSocket();
  const { t } = useLanguage();
  const [requests, setRequests] = useState([]);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (isOpen) loadRequests();
  }, [isOpen]);

  const loadRequests = async () => {
    setLoading(true);
    try {
      const data = await fetchJSON("/api/friends/requests");
      setRequests(data);
    } catch (err) {
      console.error("So'rovlarni yuklashda xato:", err);
    }
    setLoading(false);
  };

  const handleAccept = async (requestId, senderUsername) => {
    try {
      await fetchJSON("/api/friends/accept", {
        method: "POST",
        body: JSON.stringify({ requestId }),
      });
      setRequests((prev) => prev.filter((r) => r.id !== requestId));

      // Real-time notification
      if (socket) {
        socket.emit("FRIEND_ACCEPTED", {
          targetUsername: senderUsername,
          accepterUsername: user,
          accepterAvatar: avatar,
        });
      }
    } catch (err) {
      console.error("Qabul qilishda xato:", err);
    }
  };

  const handleReject = async (requestId) => {
    try {
      await fetchJSON("/api/friends/reject", {
        method: "POST",
        body: JSON.stringify({ requestId }),
      });
      setRequests((prev) => prev.filter((r) => r.id !== requestId));
    } catch (err) {
      console.error("Rad etishda xato:", err);
    }
  };

  return (
    <Modal isOpen={isOpen} onClose={onClose} title={t("friend_requests_title")}>
      <div className="p-4">
        {loading ? (
          <p className="text-center text-sm text-gray-400 py-8">{t("loading")}</p>
        ) : requests.length === 0 ? (
          <div className="text-center py-8">
            <i className="fas fa-inbox text-3xl text-gray-300 dark:text-gray-600 mb-3" />
            <p className="text-sm text-gray-400">{t("friend_requests_empty")}</p>
          </div>
        ) : (
          <div className="space-y-2 max-h-80 overflow-y-auto">
            {requests.map((r) => (
              <div
                key={r.id}
                className="flex items-center gap-3 p-3 rounded-xl bg-gray-50 dark:bg-gray-800/50"
              >
                <Avatar src={r.avatar} name={r.username} size={44} />
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-semibold text-gray-900 dark:text-white truncate">
                    {r.username}
                  </p>
                  <p className="text-xs text-gray-400">{t("friend_wants_be_friend")}</p>
                </div>
                <div className="flex gap-2 shrink-0">
                  <button
                    onClick={() => handleAccept(r.id, r.username)}
                    className="px-3 py-1.5 text-xs bg-blue-500 text-white rounded-lg hover:bg-blue-600 transition-colors font-medium"
                  >
                    {t("friend_accept")}
                  </button>
                  <button
                    onClick={() => handleReject(r.id)}
                    className="px-3 py-1.5 text-xs bg-gray-200 dark:bg-gray-700 text-gray-700 dark:text-gray-300 rounded-lg hover:bg-gray-300 dark:hover:bg-gray-600 transition-colors font-medium"
                  >
                    {t("friend_reject")}
                  </button>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </Modal>
  );
}
