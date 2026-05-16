import { useEffect, useMemo, useRef, useState } from "react";
import Avatar from "@/components/common/Avatar";
import { useAuth } from "@/context/AuthContext";
import { useLanguage } from "@/context/LanguageContext";
import { fetchJSON } from "@/utils/api";

const CALL_REGEX = /^__CALL:(audio|video):(missed|\d+)__$/;

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

function parseCallMessage(content) {
  if (!content) return null;
  const match = content.match(CALL_REGEX);
  if (!match) return null;

  return {
    type: match[1],
    missed: match[2] === "missed",
    duration: match[2] === "missed" ? 0 : Number(match[2]) || 0,
  };
}

function getCallIcon(call, currentUser, t) {
  if (call.missed) {
    return {
      icon: "fa-arrow-left",
      color: "text-[#ef6d5d]",
      rotate: "-rotate-45",
      label: t("calls_missed"),
    };
  }

  if (call.caller === currentUser) {
    return {
      icon: "fa-arrow-right",
      color: "text-[#2eb85c]",
      rotate: "-rotate-45",
      label: t("calls_outgoing"),
    };
  }

  return {
    icon: "fa-arrow-left",
    color: "text-[#2eb85c]",
    rotate: "-rotate-45",
    label: t("calls_incoming"),
  };
}

function formatCallDate(dateStr, t) {
  const d = new Date(dateStr);
  if (Number.isNaN(d.getTime())) return "";

  const now = new Date();
  const today = now.toDateString();
  const yesterday = new Date(now);
  yesterday.setDate(now.getDate() - 1);

  const time = `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
  const formatted = `${String(d.getDate()).padStart(2, "0")}.${String(d.getMonth() + 1).padStart(2, "0")}.${d.getFullYear()}`;

  if (d.toDateString() === today) return time;
  if (d.toDateString() === yesterday.toDateString()) return `${t("yesterday")} ${time}`;

  return `${formatted} ${time}`;
}

export default function CallsModal({ isOpen, onClose, onStartCall }) {
  const { user } = useAuth();
  const { t } = useLanguage();
  const [calls, setCalls] = useState([]);
  const [contacts, setContacts] = useState([]);
  const [search, setSearch] = useState("");
  const [loading, setLoading] = useState(false);
  const searchInputRef = useRef(null);

  const tr = (key, fallback) => {
    const value = t(key);
    return value === key ? fallback : value;
  };

  useEffect(() => {
    if (!isOpen) return undefined;

    const handleEscape = (event) => {
      if (event.key === "Escape") onClose?.();
    };

    document.addEventListener("keydown", handleEscape);
    return () => document.removeEventListener("keydown", handleEscape);
  }, [isOpen, onClose]);

  useEffect(() => {
    if (!isOpen || !user) return undefined;

    let cancelled = false;

    const loadCalls = async () => {
      setLoading(true);
      try {
        const inbox = await fetchJSON(`/api/inbox?username=${encodeURIComponent(user)}`);
        const normalizedInbox = inbox
          .map(normalizeInboxEntry)
          .filter(Boolean);
        const uniqueContacts = Array.from(
          new Map(normalizedInbox.map((item) => [item.username, item])).values(),
        );

        if (cancelled) return;
        setContacts(uniqueContacts);

        const history = await fetchJSON(`/api/calls/history?username=${encodeURIComponent(user)}`);
        if (cancelled) return;

        const peersByUsername = new Map(
          uniqueContacts.map((peer) => [peer.username, peer]),
        );

        const mergedHistory = history
          .map((entry) => {
            const callInfo = parseCallMessage(entry?.content);
            if (!callInfo) return null;

            const peer = peersByUsername.get(entry.peerUsername);

            return {
              id: entry.id || `${entry.peerUsername}-${entry.created_at}`,
              kind: "history",
              username: entry.peerUsername,
              full_name:
                entry.peerFullName ||
                peer?.full_name ||
                entry.peerUsername,
              avatar: entry.peerAvatar || peer?.avatar || null,
              online: peer?.online,
              caller: entry.caller,
              receiver: entry.caller === user ? entry.peerUsername : user,
              type: callInfo.type,
              missed: callInfo.missed,
              duration: callInfo.duration,
              date: entry.created_at,
            };
          })
          .filter(Boolean)
          .sort((a, b) => new Date(b.date) - new Date(a.date));

        setCalls(mergedHistory);
      } catch (error) {
        console.error("Qo'ng'iroqlar tarixini yuklashda xato:", error);
        if (!cancelled) {
          setContacts([]);
          setCalls([]);
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    };

    loadCalls();

    return () => {
      cancelled = true;
    };
  }, [isOpen, user]);

  const displayEntries = useMemo(() => {
    const query = search.trim().toLowerCase();
    const matchesQuery = (entry) => {
      if (!query) return true;
      const name = `${entry.full_name || ""} ${entry.username || ""}`.toLowerCase();
      return name.includes(query);
    };

    const filteredHistory = calls.filter(matchesQuery);
    if (filteredHistory.length > 0 || (!query && calls.length > 0)) {
      return filteredHistory;
    }

    return contacts
      .filter(matchesQuery)
      .map((peer) => ({
        id: `contact-${peer.username}`,
        kind: "contact",
        username: peer.username,
        full_name: peer.full_name || peer.username,
        avatar: peer.avatar || null,
        online: peer.online,
        date: peer.lastMessage?.created_at || "",
        preview:
          peer.lastMessage?.content ||
          (peer.lastMessage?.video
            ? tr("call_video", "Video call")
            : peer.lastMessage?.audio
              ? tr("call_audio", "Call")
              : peer.lastMessage?.image
                ? tr("chat_photo", "Photo")
                : ""),
      }));
  }, [calls, contacts, search]);

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-[70] flex items-center justify-center p-4" onClick={onClose}>
      <div className="absolute inset-0 bg-black/35" />
      <div
        className="relative flex h-[min(92vh,980px)] w-full max-w-[460px] flex-col overflow-hidden rounded-[14px] bg-white shadow-[0_24px_80px_rgba(0,0,0,0.28)]"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="flex items-center justify-between border-b border-[#ececec] px-7 py-5">
          <h3 className="text-[18px] font-semibold text-[#243246]">
            {t("calls_title")}
          </h3>
          <button
            type="button"
            className="text-[#8d939c] transition hover:text-[#5e6672]"
            aria-label="More options"
          >
            <i className="fas fa-ellipsis-vertical text-[20px]" />
          </button>
        </div>

        <button
          type="button"
          onClick={() => searchInputRef.current?.focus()}
          className="flex items-center gap-5 border-b border-[#ececec] px-7 py-5 text-left transition-colors hover:bg-[#fafafa]"
        >
          <div className="flex h-10 w-10 items-center justify-center text-[#2394ef]">
            <i className="fas fa-link text-[24px]" />
          </div>
          <span className="text-[16px] font-medium text-[#2394ef]">
            {t("calls_new")}
          </span>
        </button>

        <p className="border-b border-[#ececec] bg-[#f4f4f4] px-7 py-3 text-[13px] text-[#9aa0a6]">
          {t("calls_max_participants")}
        </p>

        <div className="border-b border-[#ececec] px-6 py-3">
          <div className="relative">
            <i className="fas fa-search absolute left-4 top-1/2 -translate-y-1/2 text-[13px] text-[#a4acb6]" />
            <input
              ref={searchInputRef}
              type="text"
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder={tr("search", "Search")}
              className="w-full rounded-full border border-[#e6e9ef] bg-[#f8f9fb] py-2.5 pl-10 pr-4 text-[14px] text-[#243246] outline-none transition focus:border-[#2394ef] focus:bg-white"
            />
          </div>
        </div>

        <div className="flex-1 overflow-y-auto">
          {loading ? (
            <div className="flex h-full flex-col items-center justify-center px-6 py-16 text-center text-[#9aa0a6]">
              <i className="fas fa-spinner fa-spin mb-3 text-3xl" />
              <p className="text-sm">{tr("loading", "Loading...")}</p>
            </div>
          ) : displayEntries.length === 0 ? (
            <div className="flex h-full flex-col items-center justify-center px-6 py-16 text-center text-[#9aa0a6]">
              <i className="fas fa-phone-slash mb-3 text-4xl opacity-30" />
              <p className="text-sm">{t("calls_empty")}</p>
            </div>
          ) : (
            <div className="divide-y divide-[#f0f0f0]">
              {displayEntries.map((call, idx) => {
                const peer = call.username;
                const { icon, color, rotate } =
                  call.kind === "history"
                    ? getCallIcon(call, user, t)
                    : {
                        icon: "fa-phone",
                        color: "text-[#9aa0a6]",
                        rotate: "",
                      };

                return (
                  <div
                    key={call.id || idx}
                    className="flex items-center gap-4 px-5 py-4 transition-colors hover:bg-[#fafafa]"
                  >
                    <Avatar src={call.avatar} name={call.full_name || peer} size={46} />
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-[15px] font-semibold text-[#111827]">
                        {call.full_name || peer}
                      </p>
                      <div className="mt-1 flex items-center gap-1.5 text-[12px] text-[#97a0aa]">
                        <i className={`fas ${icon} ${color} ${rotate} text-[12px]`} />
                        <span>
                          {call.kind === "history"
                            ? formatCallDate(call.date, t)
                            : call.preview || tr("calls_new", "Start New Call")}
                        </span>
                      </div>
                    </div>
                    <button
                      type="button"
                      onClick={(event) => {
                        event.stopPropagation();
                        onStartCall?.({
                          username: peer,
                          full_name: call.full_name || peer,
                          avatar: call.avatar || null,
                          online: call.online,
                        });
                      }}
                      className="flex h-10 w-10 items-center justify-center rounded-full text-[#9aa0a6] transition hover:bg-[#f1f3f5] hover:text-[#5f6875]"
                      aria-label={`Call ${call.full_name || peer}`}
                    >
                      <i className="fas fa-phone text-[18px]" />
                    </button>
                  </div>
                );
              })}
            </div>
          )}
        </div>

        <div className="border-t border-[#ececec] px-7 py-5">
          <button
            type="button"
            onClick={onClose}
            className="ml-auto block text-[15px] font-medium text-[#1d6fd6] transition hover:text-[#0f5ab8]"
          >
            {t("close")}
          </button>
        </div>
      </div>
    </div>
  );
}
