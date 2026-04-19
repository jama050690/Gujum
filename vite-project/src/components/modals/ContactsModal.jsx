import { useEffect, useState } from "react";
import { useAuth } from "@/context/AuthContext";
import { useSocket } from "@/context/SocketContext";
import { fetchJSON } from "@/utils/api";
import { useLanguage } from "@/context/LanguageContext";
import { getSyncedContacts, saveSyncedContacts } from "@/utils/storage";
import Avatar from "@/components/common/Avatar";
import Modal from "./Modal";

const hasContactPicker = "contacts" in navigator && "ContactsManager" in window;
const TAB_FRIENDS = "friends";
const TAB_REQUESTS = "requests";
const TAB_USERS = "users";

export default function ContactsModal({ isOpen, onClose, onSelectUser }) {
  const { user, avatar } = useAuth();
  const { socket } = useSocket();
  const { t } = useLanguage();
  const tr = (key, fallback) => {
    const value = t(key);
    return value === key ? fallback : value;
  };

  const [activeTab, setActiveTab] = useState(TAB_FRIENDS);
  const [friends, setFriends] = useState([]);
  const [requests, setRequests] = useState([]);
  const [phoneContacts, setPhoneContacts] = useState([]);
  const [searchResults, setSearchResults] = useState([]);
  const [statuses, setStatuses] = useState({});
  const [search, setSearch] = useState("");
  const [sortAZ, setSortAZ] = useState(false);
  const [loading, setLoading] = useState(false);
  const [syncing, setSyncing] = useState(false);
  const [searching, setSearching] = useState(false);

  const getContactLabel = (contact) =>
    contact.full_name || contact.fullName || contact.username || "";

  const getContactSearchText = (contact) =>
    [contact.username, contact.full_name, contact.fullName]
      .filter(Boolean)
      .join(" ")
      .toLowerCase();

  useEffect(() => {
    if (!isOpen) return;

    setSearch("");
    setSearchResults([]);
    setStatuses({});
    setPhoneContacts(getSyncedContacts());
    loadData();
  }, [isOpen]);

  const loadData = async () => {
    setLoading(true);
    try {
      const [friendsData, requestsData] = await Promise.all([
        fetchJSON("/api/friends"),
        fetchJSON("/api/friends/requests"),
      ]);
      setFriends(friendsData);
      setRequests(requestsData);
      setActiveTab(requestsData.length > 0 ? TAB_REQUESTS : TAB_FRIENDS);
    } catch (err) {
      console.error("Kontaktlarni yuklashda xato:", err);
    } finally {
      setLoading(false);
    }
  };

  const handleSync = async () => {
    if (!hasContactPicker) return;
    setSyncing(true);
    try {
      const contacts = await navigator.contacts.select(["tel"], { multiple: true });
      const phones = contacts.flatMap((c) => c.tel || []);
      if (phones.length === 0) {
        setSyncing(false);
        return;
      }
      const matched = await fetchJSON("/api/users/phone-contacts", {
        method: "POST",
        body: JSON.stringify({ phones }),
      });
      saveSyncedContacts(matched);
      setPhoneContacts(matched);
    } catch (err) {
      if (err.name !== "TypeError") {
        console.error("Kontaktlarni sinxronlashda xato:", err);
      }
    } finally {
      setSyncing(false);
    }
  };

  const handleUserSearch = async () => {
    const query = search.trim();
    if (!query) {
      setSearchResults([]);
      setStatuses({});
      return;
    }

    setSearching(true);
    try {
      const data = await fetchJSON(
        `/api/users/search?q=${encodeURIComponent(query)}`,
      );
      const filtered = data.filter((item) => item.username && item.username !== user);
      const statusEntries = await Promise.all(
        filtered.map(async (item) => {
          try {
            const status = await fetchJSON(`/api/friends/status/${item.username}`);
            return [item.username, status];
          } catch {
            return [item.username, { status: "none" }];
          }
        }),
      );

      setSearchResults(filtered);
      setStatuses(Object.fromEntries(statusEntries));
    } catch (err) {
      console.error("User qidiruvida xato:", err);
      setSearchResults([]);
      setStatuses({});
    } finally {
      setSearching(false);
    }
  };

  const handleSendRequest = async (targetUsername) => {
    try {
      await fetchJSON("/api/friends/request", {
        method: "POST",
        body: JSON.stringify({ targetUsername }),
      });
      setStatuses((prev) => ({
        ...prev,
        [targetUsername]: { status: "sent" },
      }));
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

  const handleAccept = async (requestId, senderUsername) => {
    try {
      await fetchJSON("/api/friends/accept", {
        method: "POST",
        body: JSON.stringify({ requestId }),
      });
      if (socket) {
        socket.emit("FRIEND_ACCEPTED", {
          targetUsername: senderUsername,
          accepterUsername: user,
          accepterAvatar: avatar,
        });
      }
      await loadData();
    } catch (err) {
      console.error("So'rovni qabul qilishda xato:", err);
    }
  };

  const handleReject = async (requestId) => {
    try {
      await fetchJSON("/api/friends/reject", {
        method: "POST",
        body: JSON.stringify({ requestId }),
      });
      setRequests((prev) => prev.filter((item) => item.id !== requestId));
    } catch (err) {
      console.error("So'rovni rad etishda xato:", err);
    }
  };

  const applyFilter = (list) => {
    let result = list;
    if (search.trim()) {
      const query = search.trim().toLowerCase();
      result = result.filter((item) => getContactSearchText(item).includes(query));
    }
    if (sortAZ) {
      result = [...result].sort((a, b) =>
        getContactLabel(a).localeCompare(getContactLabel(b)),
      );
    }
    return result;
  };

  const filteredFriends = applyFilter(friends);
  const friendIds = new Set(friends.map((item) => item.id));
  const filteredPhone = applyFilter(
    phoneContacts.filter((item) => !friendIds.has(item.id)),
  );
  const filteredRequests = requests.filter((item) =>
    !search.trim()
      ? true
      : item.username?.toLowerCase().includes(search.trim().toLowerCase()),
  );

  const renderContactList = (items) =>
    items.map((item) => (
      <button
        key={item.id || item.username}
        type="button"
        onClick={() => {
          onSelectUser?.(item);
          onClose();
        }}
        className="w-full flex items-center gap-3 p-2.5 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-800 text-left"
      >
        <Avatar src={item.avatar} name={getContactLabel(item)} size={40} />
        <div className="min-w-0">
          <span className="block text-sm font-medium text-gray-900 dark:text-white truncate">
            {getContactLabel(item)}
          </span>
          {item.username && getContactLabel(item) !== item.username && (
            <span className="block text-xs text-gray-400 truncate">
              @{item.username}
            </span>
          )}
        </div>
      </button>
    ));

  const renderStatusButton = (username) => {
    const status = statuses[username];
    if (!status) return null;

    switch (status.status) {
      case "friends":
        return (
          <span className="px-3 py-1 text-xs bg-green-100 dark:bg-green-900/30 text-green-600 dark:text-green-400 rounded-full">
            {tr("friend_status_friend", "Do'st")}
          </span>
        );
      case "sent":
        return (
          <span className="px-3 py-1 text-xs bg-yellow-100 dark:bg-yellow-900/30 text-yellow-600 dark:text-yellow-400 rounded-full">
            {tr("friend_status_sent", "Yuborilgan")}
          </span>
        );
      case "received":
        return (
          <span className="px-3 py-1 text-xs bg-blue-100 dark:bg-blue-900/30 text-blue-600 dark:text-blue-400 rounded-full">
            {tr("friend_status_received", "Kelgan")}
          </span>
        );
      default:
        return (
          <button
            type="button"
            onClick={() => handleSendRequest(username)}
            className="px-3 py-1 text-xs bg-blue-500 text-white rounded-full hover:bg-blue-600 transition-colors"
          >
            {tr("friend_add_button", "Qo'shish")}
          </button>
        );
    }
  };

  const renderUsersTab = () => {
    if (searching) {
      return (
        <p className="text-center text-sm text-gray-400 py-8">{tr("loading", "Yuklanmoqda...")}</p>
      );
    }

    if (!search.trim()) {
      return (
        <div className="text-center py-8">
          <i className="fas fa-user-plus text-3xl text-gray-300 dark:text-gray-600 mb-3" />
          <p className="text-sm text-gray-400">{t("friend_search_hint")}</p>
        </div>
      );
    }

    if (searchResults.length === 0) {
      return (
        <div className="text-center py-8">
          <i className="fas fa-search text-3xl text-gray-300 dark:text-gray-600 mb-3" />
          <p className="text-sm text-gray-400">{t("contacts_not_found")}</p>
        </div>
      );
    }

    return (
      <div className="space-y-2">
        {searchResults.map((item) => (
          <div
            key={item.id || item.username}
            className="flex items-center gap-3 p-2.5 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-800"
          >
            <Avatar src={item.avatar} name={getContactLabel(item)} size={40} />
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium text-gray-900 dark:text-white truncate">
                {getContactLabel(item)}
              </p>
              <p className="text-xs text-gray-400 truncate">@{item.username}</p>
            </div>
            {renderStatusButton(item.username)}
          </div>
        ))}
      </div>
    );
  };

  const renderRequestsTab = () => {
    if (filteredRequests.length === 0) {
      return (
        <div className="text-center py-8">
          <i className="fas fa-inbox text-3xl text-gray-300 dark:text-gray-600 mb-3" />
          <p className="text-sm text-gray-400">{t("friend_requests_empty")}</p>
        </div>
      );
    }

    return (
      <div className="space-y-2">
        {filteredRequests.map((item) => (
          <div
            key={item.id}
            className="flex items-center gap-3 p-3 rounded-xl bg-gray-50 dark:bg-gray-800/50"
          >
            <Avatar src={item.avatar} name={item.username} size={44} />
            <div className="flex-1 min-w-0">
              <p className="text-sm font-semibold text-gray-900 dark:text-white truncate">
                {item.username}
              </p>
              <p className="text-xs text-gray-400">{t("friend_wants_be_friend")}</p>
            </div>
            <div className="flex gap-2 shrink-0">
              <button
                type="button"
                onClick={() => handleAccept(item.id, item.username)}
                className="px-3 py-1.5 text-xs bg-blue-500 text-white rounded-lg hover:bg-blue-600 transition-colors font-medium"
              >
                {t("friend_accept")}
              </button>
              <button
                type="button"
                onClick={() => handleReject(item.id)}
                className="px-3 py-1.5 text-xs bg-gray-200 dark:bg-gray-700 text-gray-700 dark:text-gray-300 rounded-lg hover:bg-gray-300 dark:hover:bg-gray-600 transition-colors font-medium"
              >
                {t("friend_reject")}
              </button>
            </div>
          </div>
        ))}
      </div>
    );
  };

  const renderFriendsTab = () => {
    const hasAny = filteredFriends.length > 0 || filteredPhone.length > 0;
    if (!hasAny) {
      return (
        <div className="text-center py-8">
          <i className="fas fa-user-friends text-3xl text-gray-300 dark:text-gray-600 mb-3" />
          <p className="text-sm text-gray-400">
            {search.trim() ? t("contacts_not_found") : t("contacts_empty")}
          </p>
          <p className="text-xs text-gray-400 mt-1">{t("contacts_empty_hint")}</p>
        </div>
      );
    }

    return (
      <>
        {filteredFriends.length > 0 && (
          <>
            <p className="text-xs font-semibold text-gray-400 dark:text-gray-500 uppercase px-1 pt-2 pb-1">
              {t("contacts_friends_section")}
            </p>
            {renderContactList(filteredFriends)}
          </>
        )}

        {filteredPhone.length > 0 && (
          <>
            <p className="text-xs font-semibold text-gray-400 dark:text-gray-500 uppercase px-1 pt-3 pb-1">
              {t("contacts_phone_section")}
            </p>
            {renderContactList(filteredPhone)}
          </>
        )}
      </>
    );
  };

  const searchPlaceholder =
    activeTab === TAB_USERS
      ? t("friend_search_placeholder")
      : t("contacts_search");

  return (
    <Modal isOpen={isOpen} onClose={onClose} title={t("contacts_title")}>
      <div className="p-4">
        <div className="grid grid-cols-3 gap-2 mb-3">
          <TabButton
            active={activeTab === TAB_FRIENDS}
            label={t("contacts_friends_section")}
            onClick={() => setActiveTab(TAB_FRIENDS)}
          />
          <TabButton
            active={activeTab === TAB_REQUESTS}
            label={tr("friend_requests_title", "So'rovlar")}
            badge={requests.length}
            onClick={() => setActiveTab(TAB_REQUESTS)}
          />
          <TabButton
            active={activeTab === TAB_USERS}
            label={tr("friend_search_button", "Qidirish")}
            onClick={() => setActiveTab(TAB_USERS)}
          />
        </div>

        <div className="flex gap-2 mb-3">
          <div className="flex-1 relative">
            <i className="fas fa-search absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 text-sm" />
            <input
              type="text"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter" && activeTab === TAB_USERS) {
                  handleUserSearch();
                }
              }}
              placeholder={searchPlaceholder}
              className="w-full pl-9 pr-4 py-2.5 bg-gray-100 dark:bg-gray-800 rounded-xl text-sm outline-none dark:text-white"
            />
          </div>

          {activeTab === TAB_FRIENDS && (
            <button
              type="button"
              onClick={() => setSortAZ((prev) => !prev)}
              className={`px-3 rounded-xl text-sm font-medium transition-colors ${
                sortAZ
                  ? "bg-blue-500 text-white"
                  : "bg-gray-100 dark:bg-gray-800 text-gray-600 dark:text-gray-300"
              }`}
            >
              A-Z
            </button>
          )}

          {activeTab === TAB_USERS && (
            <button
              type="button"
              onClick={handleUserSearch}
              disabled={searching}
              className="px-4 py-2 bg-blue-500 text-white rounded-xl text-sm font-medium hover:bg-blue-600 transition-colors disabled:opacity-50"
            >
              {searching ? "..." : t("friend_search_button")}
            </button>
          )}
        </div>

        {activeTab === TAB_FRIENDS && hasContactPicker && (
          <div className="mb-3">
            <button
              type="button"
              onClick={handleSync}
              disabled={syncing}
              className="w-full flex items-center justify-center gap-2 py-2.5 bg-blue-50 dark:bg-blue-900/30 text-blue-600 dark:text-blue-400 rounded-xl text-sm font-medium hover:bg-blue-100 dark:hover:bg-blue-900/50 transition-colors disabled:opacity-50"
            >
              <i className={`fas ${syncing ? "fa-spinner fa-spin" : "fa-address-book"}`} />
              {t("contacts_sync_button")}
            </button>
          </div>
        )}

        <div className="max-h-80 overflow-y-auto space-y-1">
          {loading ? (
            <p className="text-center text-sm text-gray-400 py-8">{tr("loading", "Yuklanmoqda...")}</p>
          ) : activeTab === TAB_REQUESTS ? (
            renderRequestsTab()
          ) : activeTab === TAB_USERS ? (
            renderUsersTab()
          ) : (
            renderFriendsTab()
          )}
        </div>
      </div>
    </Modal>
  );
}

function TabButton({ active, label, badge = 0, onClick }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`flex items-center justify-center gap-1 rounded-xl px-3 py-2 text-sm font-medium transition-colors ${
        active
          ? "bg-blue-500 text-white"
          : "bg-gray-100 dark:bg-gray-800 text-gray-600 dark:text-gray-300"
      }`}
    >
      <span className="truncate">{label}</span>
      {badge > 0 && (
        <span
          className={`min-w-5 rounded-full px-1.5 text-[11px] leading-5 ${
            active ? "bg-white/20 text-white" : "bg-blue-500 text-white"
          }`}
        >
          {badge}
        </span>
      )}
    </button>
  );
}
