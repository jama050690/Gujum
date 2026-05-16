import { useState, useEffect, useMemo, useCallback, useRef } from "react";
import { useAuth } from "@/context/AuthContext";
import { useChat } from "@/context/ChatContext";
import { useSocket } from "@/context/SocketContext";
import { useLanguage } from "@/context/LanguageContext";
import { fetchJSON } from "@/utils/api";
import { playMessageSound } from "@/utils/sounds";
import { showDesktopNotification } from "@/utils/notifications";
import Avatar from "@/components/common/Avatar";
import UserItem from "./UserItem";
import ArchivedChatsItem from "./ArchivedChatsItem";
import ChatContextMenu from "./ChatContextMenu";

const SAVED_MESSAGES_USER = {
  username: "__SAVED_MESSAGES__",
  type: "saved",
  online: true,
};

const normalizeInboxEntry = (item) => {
  const username = item?.sender || item?.username || "";
  if (!username) return null;

  return {
    username,
    full_name:
      item?.senderFullName ||
      item?.full_name ||
      item?.fullName ||
      username,
    avatar: item?.avatar || null,
    online: Boolean(item?.online),
    lastActive: item?.lastActive || item?.last_seen || null,
    unreadCount: Number(item?.unreadcount ?? item?.unreadCount ?? 0) || 0,
    lastMessage: {
      content: item?.lastContent ?? item?.lastcontent ?? "",
      image: item?.lastImage ?? item?.lastimage ?? null,
      audio: item?.lastAudio ?? item?.lastaudio ?? null,
      video: item?.lastVideo ?? item?.lastvideo ?? null,
      created_at:
        item?.lastMessageTime ||
        item?.lastmessagetime ||
        item?.created_at ||
        "",
    },
  };
};

const sortByLastActivity = (a, b) => {
  const timeA = a?.lastMessage?.created_at || "";
  const timeB = b?.lastMessage?.created_at || "";
  if (timeA && timeB) return new Date(timeB) - new Date(timeA);
  if (timeA) return -1;
  if (timeB) return 1;
  return 0;
};

const getItemKey = (item) => item.username || item.name || `${item.type}-${item.id}`;
const isItemActive = (activeChat, item) => {
  if (!activeChat || !item) return false;
  if (activeChat.username && item.username) return activeChat.username === item.username;
  return activeChat.id === item.id && activeChat.type === item.type;
};

export default function UsersPanel({ onOpenSidebar }) {
  const { user } = useAuth();
  const { t } = useLanguage();
  const { users, activeChat, unreadMessages, typingUsers, lastMessages, dispatch } = useChat();
  const { socket } = useSocket();
  const [search, setSearch] = useState("");
  const [searchFocused, setSearchFocused] = useState(false);
  const [groups, setGroups] = useState([]);
  const [channels, setChannels] = useState([]);
  const [inboxUsers, setInboxUsers] = useState([]);
  const [chattedUsers, setChattedUsers] = useState(new Set());
  const [showArchived, setShowArchived] = useState(false);
  const [archivedChats, setArchivedChats] = useState(new Set());
  const [pinnedChats, setPinnedChats] = useState(new Set());
  const [mutedChats, setMutedChats] = useState(new Set());
  const [deletedChats, setDeletedChats] = useState(new Set());
  const [menuState, setMenuState] = useState({ open: false, x: 0, y: 0, item: null });
  const [blockedUsers, setBlockedUsers] = useState(new Set());
  const [globalResults, setGlobalResults] = useState([]);
  const [friendStatuses, setFriendStatuses] = useState({});
  const [globalLoading, setGlobalLoading] = useState(false);
  const searchTimerRef = useRef(null);

  const storageKey = (suffix) => `bootchat:${user || "guest"}:${suffix}`;

  const loadBlockedUsers = useCallback(async () => {
    try {
      const list = await fetchJSON("/api/block");
      setBlockedUsers(new Set(list.map((b) => b.username)));
    } catch {
      setBlockedUsers(new Set());
    }
  }, []);

  // Load groups, channels, and inbox on mount
  useEffect(() => {
    if (!user) return;
    loadGroupsAndChannels();
    loadInbox();
    loadBlockedUsers();
    setShowArchived(false);
    setInboxUsers([]);
    setChattedUsers(new Set());

    try {
      setArchivedChats(new Set(JSON.parse(localStorage.getItem(storageKey("archived_chats")) || "[]")));
      setPinnedChats(new Set(JSON.parse(localStorage.getItem(storageKey("pinned_chats")) || "[]")));
      setMutedChats(new Set(JSON.parse(localStorage.getItem(storageKey("muted_chats")) || "[]")));
      localStorage.removeItem(storageKey("deleted_chats"));
      setDeletedChats(new Set());
    } catch {
      setArchivedChats(new Set());
      setPinnedChats(new Set());
      setMutedChats(new Set());
      setDeletedChats(new Set());
    }
  }, [user]);

  useEffect(() => {
    if (!user) return;
    localStorage.setItem(storageKey("archived_chats"), JSON.stringify([...archivedChats]));
  }, [archivedChats, user]);

  useEffect(() => {
    if (!user) return;
    localStorage.setItem(storageKey("pinned_chats"), JSON.stringify([...pinnedChats]));
  }, [pinnedChats, user]);

  useEffect(() => {
    if (!user) return;
    localStorage.setItem(storageKey("muted_chats"), JSON.stringify([...mutedChats]));
  }, [mutedChats, user]);

  // Socket event listeners
  useEffect(() => {
    if (!socket) return;

    const handleUsersList = (usersList) => {
      dispatch({ type: "SET_ONLINE_USERS", payload: usersList });
    };

    const handleStatusChanged = (data) => {
      dispatch({ type: "USER_STATUS_CHANGED", payload: data });
    };

    const handleNewMessage = (data) => {
      // Kimdan kelgan bo'lsa ham lastMessage yangilaymiz
      const chatWith = data.user === user ? data.receiver : data.user;
      if (chatWith && chatWith !== user) {
        setChattedUsers((prev) => {
          const next = new Set(prev);
          next.add(chatWith);
          return next;
        });
      }
      dispatch({
        type: "SET_LAST_MESSAGE",
        payload: {
          user: chatWith,
          message: {
            content: data.message || "",
            image: data.image,
            audio: data.audio,
            video: data.video,
            created_at: new Date().toISOString(),
          },
        },
      });
      if (chatWith && chatWith !== user) {
        setInboxUsers((prev) => {
          const existing = prev.find((entry) => entry.username === chatWith);
          const liveUser = users.find((entry) => entry.username === chatWith);
          const activeDirectChat =
            activeChat?.username === chatWith && !activeChat?.type ? activeChat : null;

          const nextEntry = {
            username: chatWith,
            full_name:
              liveUser?.full_name ||
              existing?.full_name ||
              activeDirectChat?.full_name ||
              chatWith,
            avatar: liveUser?.avatar || existing?.avatar || activeDirectChat?.avatar || null,
            online: Boolean(liveUser?.online ?? existing?.online),
            unreadCount: existing?.unreadCount || 0,
            lastMessage: {
              content: data.message || "",
              image: data.image || null,
              audio: data.audio || null,
              video: data.video || null,
              created_at: new Date().toISOString(),
            },
          };

          return [nextEntry, ...prev.filter((entry) => entry.username !== chatWith)];
        });
      }

      // Faqat boshqa userdan kelgan va ochiq chat bo'lmasa unread qo'shamiz
      if (data.user !== user) {
        if (!activeChat || activeChat.username !== data.user) {
          dispatch({ type: "SET_UNREAD", payload: { user: data.user } });
          playMessageSound();
          showDesktopNotification(data.user, data.message || "Yangi xabar");
        }
      }
    };

    const handleTyping = (data) => {
      if (data.receiver === user && data.user !== user) {
        dispatch({ type: "SET_TYPING", payload: data });
        setTimeout(() => dispatch({ type: "CLEAR_TYPING", payload: data.user }), 2000);
      }
    };

    socket.on("ONLINE_USERS_LIST", handleUsersList);
    socket.on("USER_STATUS_CHANGED", handleStatusChanged);
    socket.on("NEW_MESSAGE", handleNewMessage);
    socket.on("TYPING", handleTyping);

    return () => {
      socket.off("ONLINE_USERS_LIST", handleUsersList);
      socket.off("USER_STATUS_CHANGED", handleStatusChanged);
      socket.off("NEW_MESSAGE", handleNewMessage);
      socket.off("TYPING", handleTyping);
    };
  }, [socket, user, activeChat, users, dispatch]);

  const loadGroupsAndChannels = async () => {
    try {
      const [g, c] = await Promise.all([
        fetchJSON(`/api/groups?username=${user}`),
        fetchJSON(`/api/channels?username=${user}`),
      ]);
      setGroups(g);
      setChannels(c);
    } catch (err) {
      console.error("Groups/Channels yuklashda xato:", err);
    }
  };

  const loadInbox = async () => {
    try {
      const inbox = await fetchJSON(`/api/inbox?username=${user}`);
      const normalizedInbox = inbox
        .map(normalizeInboxEntry)
        .filter(Boolean)
        .sort(sortByLastActivity);

      const dedupedInbox = [];
      const seenUsers = new Set();
      normalizedInbox.forEach((entry) => {
        if (seenUsers.has(entry.username)) return;
        seenUsers.add(entry.username);
        dedupedInbox.push(entry);
      });

      const chatted = new Set();
      dedupedInbox.forEach((entry) => {
        chatted.add(entry.username);
        if (
          entry.lastMessage.content ||
          entry.lastMessage.image ||
          entry.lastMessage.audio ||
          entry.lastMessage.video ||
          entry.lastMessage.created_at
        ) {
          dispatch({
            type: "SET_LAST_MESSAGE",
            payload: {
              user: entry.username,
              message: entry.lastMessage,
            },
          });
        }
        if (entry.unreadCount >= 0) {
          dispatch({
            type: "SET_UNREAD_COUNT",
            payload: {
              user: entry.username,
              count: entry.unreadCount,
            },
          });
        }
      });
      const lastActiveBatch = dedupedInbox
        .filter((e) => e.lastActive)
        .map((e) => ({ username: e.username, lastActive: e.lastActive }));
      if (lastActiveBatch.length > 0) {
        dispatch({ type: "SET_LAST_ACTIVE_BATCH", payload: lastActiveBatch });
      }

      setInboxUsers(dedupedInbox);
      setChattedUsers(chatted);
    } catch (err) {
      console.error("Inbox yuklashda xato:", err);
    }
  };

  // Global search — backend'dan userlarni qidirish
  useEffect(() => {
    if (searchTimerRef.current) clearTimeout(searchTimerRef.current);

    if (!search.trim() || search.trim().length < 2) {
      setGlobalResults([]);
      setFriendStatuses({});
      return;
    }

    searchTimerRef.current = setTimeout(async () => {
      setGlobalLoading(true);
      try {
        const data = await fetchJSON(`/api/users/search?q=${encodeURIComponent(search.trim())}`);
        const filtered = data.filter((u) => u.username !== user);
        setGlobalResults(filtered);

        // Do'stlik statuslarini tekshirish
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
        setFriendStatuses(statusMap);
      } catch {
        setGlobalResults([]);
      }
      setGlobalLoading(false);
    }, 400);

    return () => {
      if (searchTimerRef.current) clearTimeout(searchTimerRef.current);
    };
  }, [search, user]);

  const handleSendFriendRequest = async (targetUsername) => {
    try {
      await fetchJSON("/api/friends/request", {
        method: "POST",
        body: JSON.stringify({ targetUsername }),
      });
      setFriendStatuses((prev) => ({ ...prev, [targetUsername]: { status: "sent" } }));
      if (socket) {
        socket.emit("FRIEND_REQUEST", {
          targetUsername,
          senderUsername: user,
        });
      }
    } catch (err) {
      alert(err.message || "Xatolik");
    }
  };

  const handleGlobalUserClick = (item) => {
    setSearch("");
    setGlobalResults([]);
    handleUserClick({ username: item.username, avatar: item.avatar, full_name: item.full_name, online: false });
  };

  const handleUserClick = (item) => {
    dispatch({ type: "SET_ACTIVE_CHAT", payload: item });
    dispatch({ type: "CLEAR_UNREAD", payload: item.username || item.name });
  };

  const handleItemContextMenu = (e, item) => {
    if (!item || item.username === "__SAVED_MESSAGES__") return;
    e.preventDefault();
    const menuWidth = 260;
    const menuHeight = 320;
    const x = Math.min(e.clientX, window.innerWidth - menuWidth - 12);
    const y = Math.min(e.clientY, window.innerHeight - menuHeight - 12);
    setMenuState({ open: true, x, y, item });
  };

  const closeMenu = () => setMenuState({ open: false, x: 0, y: 0, item: null });

  const menuItems = useMemo(() => {
    if (!menuState.item) return [];
    const item = menuState.item;
    const key = getItemKey(item);
    const isArchived = archivedChats.has(key);
    const isPinned = pinnedChats.has(key);
    const isMuted = mutedChats.has(key);
    const unreadNow = unreadMessages.get(key) || 0;

    return [
      {
        id: "open-window",
        label: t("chat_open_window"),
        icon: "fa-clone",
        onClick: () => {
          const chat = encodeURIComponent(key);
          const basePath = import.meta.env.VITE_BASE_PATH || "/";
          window.open(`${window.location.origin}${basePath}?chat=${chat}`, "_blank", "noopener,noreferrer");
        },
      },
      {
        id: "archive",
        label: isArchived ? t("chat_unarchive") : t("chat_archive"),
        icon: isArchived ? "fa-box-open" : "fa-box-archive",
        onClick: () => {
          setArchivedChats((prev) => {
            const next = new Set(prev);
            if (next.has(key)) next.delete(key);
            else next.add(key);
            return next;
          });
          if (!isArchived && activeChat && getItemKey(activeChat) === key) {
            dispatch({ type: "CLOSE_CHAT" });
          }
        },
      },
      {
        id: "pin",
        label: isPinned ? t("chat_unpin") : t("chat_pin"),
        icon: "fa-thumbtack",
        onClick: () => {
          setPinnedChats((prev) => {
            const next = new Set(prev);
            if (next.has(key)) next.delete(key);
            else next.add(key);
            return next;
          });
        },
      },
      {
        id: "mute",
        label: isMuted ? t("chat_unmute") : t("chat_mute"),
        icon: isMuted ? "fa-volume-high" : "fa-volume-xmark",
        onClick: () => {
          setMutedChats((prev) => {
            const next = new Set(prev);
            if (next.has(key)) next.delete(key);
            else next.add(key);
            return next;
          });
        },
      },
      {
        id: "mark-unread",
        label: t("chat_mark_unread"),
        icon: "fa-comment-dots",
        onClick: () => {
          dispatch({
            type: "SET_UNREAD_COUNT",
            payload: { user: key, count: unreadNow > 0 ? unreadNow : 1 },
          });
        },
      },
      {
        id: "clear-history",
        label: t("chat_clear_history"),
        icon: "fa-check",
        onClick: () => {
          dispatch({ type: "CLEAR_LAST_MESSAGE", payload: key });
          dispatch({ type: "CLEAR_UNREAD", payload: key });
          if (activeChat && getItemKey(activeChat) === key) {
            dispatch({ type: "SET_MESSAGES", payload: [] });
          }
        },
      },
      {
        id: "delete-chat",
        label: t("chat_delete_chat"),
        icon: "fa-trash",
        dividerTop: true,
        danger: true,
        onClick: () => {
          setDeletedChats((prev) => new Set(prev).add(key));
          setArchivedChats((prev) => {
            const next = new Set(prev);
            next.delete(key);
            return next;
          });
          setPinnedChats((prev) => {
            const next = new Set(prev);
            next.delete(key);
            return next;
          });
          setMutedChats((prev) => {
            const next = new Set(prev);
            next.delete(key);
            return next;
          });
          dispatch({ type: "CLEAR_LAST_MESSAGE", payload: key });
          dispatch({ type: "CLEAR_UNREAD", payload: key });
          if (activeChat && getItemKey(activeChat) === key) {
            dispatch({ type: "CLOSE_CHAT" });
          }
        },
      },
      ...(item.username && !item.type ? [
        {
          id: "block-user",
          label: blockedUsers.has(item.username) ? t("chat_unblock") : t("chat_block"),
          icon: blockedUsers.has(item.username) ? "fa-unlock" : "fa-ban",
          danger: true,
          onClick: async () => {
            try {
              if (blockedUsers.has(item.username)) {
                await fetchJSON(`/api/block/${item.username}`, { method: "DELETE" });
                setBlockedUsers((prev) => {
                  const next = new Set(prev);
                  next.delete(item.username);
                  return next;
                });
              } else {
                await fetchJSON("/api/block", {
                  method: "POST",
                  body: JSON.stringify({ targetUsername: item.username }),
                });
                setBlockedUsers((prev) => new Set(prev).add(item.username));
              }
            } catch (err) {
              console.error("Bloklashda xato:", err);
            }
          },
        },
        {
          id: "spam-report",
          label: t("block_mark_spam"),
          icon: "fa-shield-halved",
          danger: true,
          onClick: async () => {
            const reason = prompt(t("block_spam_reason"));
            if (reason === null) return;
            try {
              await fetchJSON("/api/spam/report", {
                method: "POST",
                body: JSON.stringify({ targetUsername: item.username, reason }),
              });
              setBlockedUsers((prev) => new Set(prev).add(item.username));
              alert(t("block_spam_done"));
            } catch (err) {
              console.error("Spam reportda xato:", err);
            }
          },
        },
      ] : []),
    ];
  }, [menuState.item, archivedChats, pinnedChats, mutedChats, unreadMessages, activeChat, dispatch, blockedUsers]);

  // Sort users by pin + last message time
  const visibleItems = useMemo(() => {
    const directUsers = inboxUsers
      .filter((entry) => entry.username !== user)
      .map((entry) => {
        const liveUser = users.find((item) => item.username === entry.username);
        return {
          ...entry,
          avatar: liveUser?.avatar || entry.avatar,
          full_name: liveUser?.full_name || entry.full_name,
          online: Boolean(liveUser?.online ?? entry.online),
        };
      });
    const allItems = [...directUsers, ...groups, ...channels];
    const base = allItems.filter((item) => {
      const key = getItemKey(item);
      if (deletedChats.has(key)) return false;
      return showArchived ? archivedChats.has(key) : !archivedChats.has(key);
    });

    base.sort((a, b) => {
      const keyA = getItemKey(a);
      const keyB = getItemKey(b);
      const pinA = pinnedChats.has(keyA) ? 1 : 0;
      const pinB = pinnedChats.has(keyB) ? 1 : 0;
      if (pinA !== pinB) return pinB - pinA;

      const timeA = lastMessages.get(keyA)?.created_at || "";
      const timeB = lastMessages.get(keyB)?.created_at || "";
      if (timeA && timeB) return new Date(timeB) - new Date(timeA);
      if (timeA) return -1;
      if (timeB) return 1;
      return 0;
    });

    if (!showArchived) return [SAVED_MESSAGES_USER, ...base];
    return base;
  }, [users, inboxUsers, groups, channels, lastMessages, user, deletedChats, showArchived, archivedChats, pinnedChats]);

  const filteredItems = search
    ? visibleItems.filter((item) => {
        const q = search.toLowerCase();
        const name = item.username || item.name || "";
        const fullName = item.full_name || "";
        return name.toLowerCase().includes(q) || fullName.toLowerCase().includes(q);
      })
    : visibleItems;

  return (
    <div className="flex flex-col h-full bg-white dark:bg-[#212121]">
      {/* Header */}
      <div className="flex items-center gap-1 px-2 py-1.5 bg-white dark:bg-[#242f3d] border-b border-gray-200 dark:border-gray-700 shrink-0">
        {showArchived ? (
          <button
            onClick={() => setShowArchived(false)}
            className="w-10 h-10 flex items-center justify-center text-gray-500 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-white/10 rounded-full transition-colors cursor-pointer active:scale-90"
          >
            <i className="fas fa-arrow-left text-lg" />
          </button>
        ) : (
          <button
            onClick={onOpenSidebar}
            className="w-10 h-10 flex items-center justify-center text-gray-500 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-white/10 rounded-full transition-colors cursor-pointer active:scale-90"
          >
            <i className="fas fa-bars text-lg" />
          </button>
        )}
        <div className="flex-1 relative" onClick={(e) => e.stopPropagation()}>
          {showArchived ? (
            <div className="h-10 flex items-center px-3">
              <span className="text-gray-900 dark:text-white font-medium text-base">{t("archive_title")}</span>
            </div>
          ) : (
            <>
              <i className={`fas fa-search absolute left-3 top-1/2 -translate-y-1/2 text-sm transition-colors ${searchFocused ? "text-[#3390ec]" : "text-gray-400 dark:text-gray-500"}`} />
              <input
                type="text"
                placeholder={t("search")}
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                onFocus={() => setSearchFocused(true)}
                onBlur={() => setSearchFocused(false)}
                className="w-full pl-9 pr-4 py-2 bg-gray-100 dark:bg-[#3b4654] rounded-full text-sm text-gray-900 dark:text-white placeholder-gray-400 dark:placeholder-gray-500 outline-none focus:bg-gray-50 dark:focus:bg-[#2b3640] transition-colors"
              />
            </>
          )}
        </div>
      </div>

      {/* User list */}
      <div className="flex-1 overflow-y-auto">
        {showArchived ? (
          filteredItems.length === 0 ? (
            <div className="px-5 py-10 text-center">
              <div className="w-16 h-16 mx-auto mb-3 rounded-full bg-gray-200 dark:bg-gray-700 flex items-center justify-center">
                <i className="fas fa-box-archive text-gray-500 dark:text-gray-300 text-xl" />
              </div>
              <p className="text-sm font-medium text-gray-700 dark:text-gray-200">{t("archive_title")}</p>
              <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">
                {t("archive_empty")}
              </p>
            </div>
          ) : (
            filteredItems.map((item) => {
              const key = getItemKey(item);
              return (
                <UserItem
                  key={key}
                  item={item}
                  isActive={isItemActive(activeChat, item)}
                  onClick={handleUserClick}
                  onContextMenu={handleItemContextMenu}
                  unread={unreadMessages.get(item.username || item.name) || 0}
                  typing={typingUsers.has(item.username)}
                  lastMessage={lastMessages.get(item.username || item.name)}
                  pinned={pinnedChats.has(key)}
                  muted={mutedChats.has(key)}
                />
              );
            })
          )
        ) : (
          <>
            {!search && <ArchivedChatsItem storiesCount={1} onClick={() => setShowArchived(true)} />}
            {filteredItems.map((item) => {
              const key = getItemKey(item);
              return (
                <UserItem
                  key={key}
                  item={item}
                  isActive={isItemActive(activeChat, item)}
                  onClick={handleUserClick}
                  onContextMenu={handleItemContextMenu}
                  unread={unreadMessages.get(item.username || item.name) || 0}
                  typing={typingUsers.has(item.username)}
                  lastMessage={lastMessages.get(item.username || item.name)}
                  pinned={pinnedChats.has(key)}
                  muted={mutedChats.has(key)}
                />
              );
            })}

            {/* Global search results */}
            {search.trim().length >= 2 && (
              <>
                {globalLoading && (
                  <div className="px-4 py-3 text-center">
                    <i className="fas fa-spinner fa-spin text-gray-400" />
                  </div>
                )}
                {!globalLoading && globalResults.length > 0 && (
                  <>
                    <div className="px-4 py-2 bg-gray-50 dark:bg-[#1a1a1a] border-y border-gray-100 dark:border-gray-800">
                      <p className="text-xs font-semibold text-gray-500 dark:text-gray-400 uppercase">
                        {t("search_global_results")}
                      </p>
                    </div>
                    {globalResults
                      .filter((gr) => !filteredItems.some((fi) => fi.username === gr.username))
                      .map((u) => {
                        return (
                          <div
                            key={u.username}
                            className="flex items-center gap-3 px-3 py-2.5 hover:bg-gray-100 dark:hover:bg-[#2b2b2b] transition-colors cursor-pointer"
                            onClick={() => handleGlobalUserClick(u)}
                          >
                            <div className="flex items-center gap-3 flex-1 min-w-0">
                              <Avatar src={u.avatar} name={u.username} size={46} />
                              <div className="min-w-0">
                                <p className="text-sm font-medium text-gray-900 dark:text-white truncate">{u.full_name || u.username}</p>
                                <p className="text-xs text-gray-400 truncate">
                                  {t("search_tap_to_chat")}
                                </p>
                              </div>
                            </div>
                            <span className="shrink-0 px-2.5 py-1 text-xs bg-blue-100 dark:bg-blue-900/30 text-blue-600 dark:text-blue-400 rounded-full">
                              {t("search_tap_to_chat")}
                            </span>
                          </div>
                        );
                      })}
                  </>
                )}
                {!globalLoading && globalResults.length === 0 && filteredItems.length === 0 && (
                  <div className="px-5 py-10 text-center">
                    <i className="fas fa-search text-3xl text-gray-300 dark:text-gray-600 mb-3" />
                    <p className="text-sm text-gray-400">{t("chat_nothing_found")}</p>
                  </div>
                )}
              </>
            )}
          </>
        )}
      </div>
      {menuState.open && (
        <ChatContextMenu
          x={menuState.x}
          y={menuState.y}
          items={menuItems}
          onClose={closeMenu}
        />
      )}
    </div>
  );
}
