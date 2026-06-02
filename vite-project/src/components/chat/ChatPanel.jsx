import { useState, useEffect, useCallback, useMemo } from "react";
import { BRAND_LOGO_URL } from "@/utils/branding";
import { useAuth } from "@/context/AuthContext";
import { useChat } from "@/context/ChatContext";
import { useSocket } from "@/context/SocketContext";
import { useLanguage } from "@/context/LanguageContext";
import { fetchJSON } from "@/utils/api";
import { getSavedMessages, saveMessage, deleteSavedMessage, getSettings } from "@/utils/storage";
import ChatHeader from "./ChatHeader";
import MessageList from "./MessageList";
import MessageInput from "./MessageInput";
import ForwardModal from "@/components/modals/ForwardModal";

export default function ChatPanel({ onBack, onOpenSidebar, onInfo, onCall, onVideoCall }) {
  const { user, avatar } = useAuth();
  const { activeChat, messages, typingUsers, onlineUsers, lastActiveUsers, dispatch } = useChat();
  const { socket } = useSocket();
  const { t } = useLanguage();
  const settings = getSettings();
  const [searchQuery, setSearchQuery] = useState("");
  const [replyTo, setReplyTo] = useState(null);
  const [blockedByMe, setBlockedByMe] = useState(false);
  const [blockedByThem, setBlockedByThem] = useState(false);
  const [forwardMsg, setForwardMsg] = useState(null);

  useEffect(() => {
    if (!activeChat) return;
    setSearchQuery("");
    setReplyTo(null);
    setBlockedByMe(false);
    setBlockedByThem(false);
    loadMessages();
    checkBlocked();
  }, [activeChat]);

  const checkBlocked = async () => {
    if (!activeChat?.username || activeChat.username === "__SAVED_MESSAGES__" || activeChat.type) return;
    try {
      const data = await fetchJSON(`/api/block/check/${activeChat.username}`);
      setBlockedByMe(data.iBlockedThem);
      setBlockedByThem(data.theyBlockedMe);
    } catch {
      setBlockedByMe(false);
      setBlockedByThem(false);
    }
  };

  useEffect(() => {
    if (!socket || !activeChat) return;

    const handleNewMessage = (data) => {
      const isCurrent =
        activeChat.username === "__SAVED_MESSAGES__"
          ? false
          : data.user === activeChat.username || data.receiver === activeChat.username;

      if (isCurrent) {
        dispatch({
          type: "ADD_MESSAGE",
          payload: {
            id: data.id,
            username: data.user,
            avatar: data.avatar,
            content: data.message ?? data.content ?? "",
            image: data.image,
            audio: data.audio,
            video: data.video,
            reply_to_username: data.replyTo?.username || null,
            reply_to_content: data.replyTo?.content || null,
            created_at: data.created_at || new Date().toISOString(),
            read: data.user !== user, // men qabul qilayotgan bo'lsam true (o'qiyapman)
          },
        });

        if (data.user !== user && activeChat.username) {
          fetchJSON("/api/messages/mark-read", {
            method: "POST",
            body: JSON.stringify({ username: user, chatWith: activeChat.username }),
          }).then(() => {
            // Senderga xabar berish - xabarlar o'qildi
            socket.emit("MESSAGES_READ", { reader: user, sender: data.user });
          }).catch(() => {});
        }
      }
    };

    const handleGroupMessage = (data) => {
      if (activeChat.type === "group" && data.groupId === activeChat.id) {
        dispatch({ type: "ADD_MESSAGE", payload: data });
      }
    };

    const handleChannelMessage = (data) => {
      if (activeChat.type === "channel" && data.channelId === activeChat.id) {
        dispatch({ type: "ADD_MESSAGE", payload: data });
      }
    };

    const handleMessageBlocked = (data) => {
      if (activeChat?.username === data.receiver) {
        setBlockedByThem(true);
      }
    };

    const handleMessageDeleted = (data) => {
      if (data.messageId) {
        dispatch({ type: "DELETE_MESSAGE", payload: data.messageId });
      }
    };

    const handleMessagesRead = (data) => {
      // Receiver mening xabarlarimni o'qidi — checkmarkni double qilish
      if (data.reader === activeChat?.username) {
        dispatch({ type: "MARK_MESSAGES_READ", payload: data.reader });
      }
    };

    socket.on("NEW_MESSAGE", handleNewMessage);
    socket.on("GROUP_MESSAGE", handleGroupMessage);
    socket.on("CHANNEL_MESSAGE", handleChannelMessage);
    socket.on("MESSAGE_BLOCKED", handleMessageBlocked);
    socket.on("MESSAGE_DELETED", handleMessageDeleted);
    socket.on("MESSAGES_READ", handleMessagesRead);
    return () => {
      socket.off("NEW_MESSAGE", handleNewMessage);
      socket.off("GROUP_MESSAGE", handleGroupMessage);
      socket.off("CHANNEL_MESSAGE", handleChannelMessage);
      socket.off("MESSAGE_BLOCKED", handleMessageBlocked);
      socket.off("MESSAGE_DELETED", handleMessageDeleted);
      socket.off("MESSAGES_READ", handleMessagesRead);
    };
  }, [socket, activeChat, user]);

  const loadMessages = async () => {
    if (!activeChat) return;

    if (activeChat.username === "__SAVED_MESSAGES__") {
      const saved = getSavedMessages();
      dispatch({ type: "SET_MESSAGES", payload: saved });
      return;
    }

    try {
      let msgs;
      if (activeChat.type === "group") {
        msgs = await fetchJSON(`/api/groups/${activeChat.id}/messages`);
      } else if (activeChat.type === "channel") {
        msgs = await fetchJSON(`/api/channels/${activeChat.id}/messages`);
      } else {
        msgs = await fetchJSON(`/api/messages?user1=${user}&user2=${activeChat.username}`);
        // is_read ni read ga map qilish
        msgs = msgs.map(m => ({ ...m, read: m.is_read ?? false }));

        // Xabarlar ochilganda senderga xabar berish
        if (socket && activeChat.username) {
          socket.emit("MESSAGES_READ", { reader: user, sender: activeChat.username });
        }
      }
      dispatch({ type: "SET_MESSAGES", payload: msgs });
    } catch (err) {
      console.error("Xabarlarni yuklashda xato:", err);
    }
  };

  const handleSend = useCallback(
    async (data) => {
      if (!activeChat) return;

      if (activeChat.username === "__SAVED_MESSAGES__") {
        const msg = {
          username: user,
          avatar,
          content: data.message || "",
          image: data.image || null,
          audio: data.audio || null,
          created_at: new Date().toISOString(),
        };
        saveMessage(msg);
        dispatch({ type: "ADD_MESSAGE", payload: { ...msg, savedAt: Date.now() } });
        setReplyTo(null);
        return;
      }

      if (activeChat.type === "group") {
        if (!socket) return;
        socket.emit("GROUP_MESSAGE", {
          groupId: activeChat.id,
          user,
          message: data.message || "",
          image: data.image || null,
          audio: data.audio || null,
          avatar,
        });
      } else if (activeChat.type === "channel") {
        if (!socket) return;
        socket.emit("CHANNEL_MESSAGE", {
          channelId: activeChat.id,
          user,
          message: data.message || "",
          image: data.image || null,
          audio: data.audio || null,
          avatar,
        });
      } else {
        const payload = {
          receiver: activeChat.username || activeChat.name,
          message: data.message || "",
          image: data.image || null,
          audio: data.audio || null,
          video: data.video || null,
          replyTo: replyTo ? { username: replyTo.username, content: replyTo.content } : null,
        };

        try {
          const created = await fetchJSON("/api/messages", {
            method: "POST",
            body: JSON.stringify(payload),
          });

          dispatch({
            type: "ADD_MESSAGE",
            payload: {
              id: created.id,
              username: created.username || user,
              avatar: created.avatar || avatar,
              content: created.content ?? payload.message,
              image: created.image || null,
              audio: created.audio || null,
              video: created.video || null,
              reply_to_username: created.reply_to_username || null,
              reply_to_content: created.reply_to_content || null,
              created_at: created.created_at || new Date().toISOString(),
              read: Boolean(created.is_read),
            },
          });

          socket?.emit("NEW_MESSAGE", {
            user,
            receiver: payload.receiver,
            message: payload.message,
            image: payload.image,
            audio: payload.audio,
            video: payload.video,
            avatar,
            replyTo: payload.replyTo,
            id: created.id,
            created_at: created.created_at,
            persisted: true,
          });
        } catch (err) {
          console.error("Xabar yuborishda xato:", err);
        }
      }
      setReplyTo(null);
    },
    [socket, activeChat, user, avatar, replyTo, dispatch],
  );

  const handleTyping = useCallback(() => {
    if (!socket || !activeChat) return;
    socket.emit("TYPING", { user, receiver: activeChat.username });
  }, [socket, activeChat, user]);

  const handleSaveMessage = useCallback((msg) => {
    saveMessage(msg);
  }, []);

  const handleDeleteMessage = useCallback(async (msg) => {
    if (msg.savedAt) {
      const remaining = deleteSavedMessage(msg.savedAt);
      dispatch({ type: "SET_MESSAGES", payload: remaining });
      return;
    }
    if (!msg.id) return;
    try {
      await fetchJSON(`/api/messages/${msg.id}`, { method: "DELETE" });
      dispatch({ type: "DELETE_MESSAGE", payload: msg.id });
      // Narigi foydalanuvchiga ham xabar berish
      if (socket && activeChat?.username) {
        socket.emit("MESSAGE_DELETED", { target: activeChat.username, messageId: msg.id });
      }
    } catch (err) {
      console.error("Xabarni o'chirishda xato:", err);
    }
  }, [dispatch]);

  const handleReply = useCallback((msg) => {
    setReplyTo(msg);
  }, []);

  const handleCopy = useCallback((msg) => {
    if (msg.content) navigator.clipboard.writeText(msg.content);
  }, []);

  const handleForward = useCallback((msg) => {
    setForwardMsg(msg);
  }, []);

  const handleForwardToChat = useCallback(async (msg, chat) => {
    if (!socket) return;
    if (chat.type === "group") {
      socket.emit("GROUP_MESSAGE", {
        groupId: chat.id,
        user,
        message: msg.content || "",
        image: msg.image || null,
        audio: msg.audio || null,
        avatar,
      });
    } else if (chat.type === "channel") {
      socket.emit("CHANNEL_MESSAGE", {
        channelId: chat.id,
        user,
        message: msg.content || "",
        image: msg.image || null,
        audio: msg.audio || null,
        avatar,
      });
    } else {
      socket.emit("NEW_MESSAGE", {
        user,
        receiver: chat.username,
        message: msg.content || "",
        image: msg.image || null,
        audio: msg.audio || null,
        avatar,
      });
    }
  }, [socket, user, avatar]);

  // Filter messages by search query
  const filteredMessages = useMemo(() => {
    if (!searchQuery.trim()) return messages;
    const q = searchQuery.toLowerCase();
    return messages.filter((msg) =>
      msg.content && msg.content.toLowerCase().includes(q)
    );
  }, [messages, searchQuery]);

  if (!activeChat) {
    return (
      <div className="hidden md:flex flex-col items-center justify-center h-full tg-chat-bg">
        <div className="text-center">
          <div className="w-28 h-28 mx-auto mb-5 rounded-3xl bg-white/20 dark:bg-white/5 flex items-center justify-center overflow-hidden p-3">
            <img src={BRAND_LOGO_URL} alt="Gujum logo" className="h-full w-full object-contain opacity-70" />
          </div>
          <h2 className="text-lg font-medium text-white/60">Gujum</h2>
          <p className="text-white/40 mt-1 text-sm">{t("chat_select_user")}</p>
        </div>
      </div>
    );
  }

  const typingUser = [...typingUsers.keys()].find((u) => u === activeChat.username) || null;
  const isSaved = activeChat.username === "__SAVED_MESSAGES__";

  return (
    <div className="flex flex-col h-full min-h-0 bg-white dark:bg-[#0f0f23]">
      <ChatHeader
        chat={activeChat}
        isOnline={onlineUsers.has(activeChat.username)}
        lastActive={lastActiveUsers.get(activeChat.username)}
        onBack={onBack}
        onOpenSidebar={onOpenSidebar}
        onInfo={onInfo}
        onCall={() => onCall?.(activeChat)}
        onVideoCall={() => onVideoCall?.(activeChat)}
        onSearch={setSearchQuery}
      />
      {searchQuery && (
        <div className="bg-white dark:bg-[#242f3d] px-4 py-1.5 text-xs text-gray-500 dark:text-gray-400 border-b border-gray-200 dark:border-gray-700">
          {filteredMessages.length > 0
            ? `${filteredMessages.length} ${t("chat_results_found")}`
            : t("chat_nothing_found")}
        </div>
      )}
      <MessageList
        messages={filteredMessages}
        currentUser={user}
        typingUser={typingUser}
        onReply={handleReply}
        onCopy={handleCopy}
        onSave={!isSaved ? handleSaveMessage : undefined}
        onDelete={handleDeleteMessage}
        onForward={handleForward}
        chatBg={settings.chatBg}
        searchQuery={searchQuery}
        allowDownload={activeChat.type ? (activeChat.allow_download || false) : true}
      />
      {blockedByMe && !isSaved && !activeChat.type ? (
        <div className="flex items-center justify-center gap-2 px-4 py-3 bg-red-50 dark:bg-red-900/20 border-t border-red-200 dark:border-red-800">
          <i className="fas fa-ban text-red-500" />
          <span className="text-sm text-red-600 dark:text-red-400">
            {t("chat_user_blocked")}
          </span>
          <button
            onClick={async () => {
              try {
                await fetchJSON(`/api/block/${activeChat.username}`, { method: "DELETE" });
                setBlockedByMe(false);
              } catch (err) {
                console.error("Blokdan chiqarishda xato:", err);
              }
            }}
            className="ml-2 px-3 py-1 text-xs bg-red-500 text-white rounded-full hover:bg-red-600 transition-colors"
          >
            {t("chat_unblock")}
          </button>
        </div>
      ) : blockedByThem && !isSaved && !activeChat.type ? (
        <div className="flex items-center justify-center gap-2 px-4 py-3 bg-gray-100 dark:bg-gray-800 border-t border-gray-200 dark:border-gray-700">
          <i className="fas fa-lock text-gray-400" />
          <span className="text-sm text-gray-500 dark:text-gray-400">
            {t("chat_blocked_by_user")}
          </span>
        </div>
      ) : (
        <MessageInput
          onSend={handleSend}
          onTyping={handleTyping}
          replyTo={replyTo}
          onCancelReply={() => setReplyTo(null)}
        />
      )}

      <ForwardModal
        isOpen={!!forwardMsg}
        onClose={() => setForwardMsg(null)}
        message={forwardMsg}
        onForward={handleForwardToChat}
      />
    </div>
  );
}
