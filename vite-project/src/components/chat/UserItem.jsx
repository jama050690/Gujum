import Avatar from "@/components/common/Avatar";
import { useLanguage } from "@/context/LanguageContext";
import { formatChatListTime } from "@/utils/formatters";
import { parseLocationMessage } from "@/utils/location";

export default function UserItem({ item, isActive, onClick, unread, typing, lastMessage, onContextMenu, pinned, muted }) {
  const { t } = useLanguage();
  const isSaved = item.username === "__SAVED_MESSAGES__";
  const locationPreview = parseLocationMessage(lastMessage?.content);

  return (
    <div
      onClick={() => onClick(item)}
      onContextMenu={(e) => onContextMenu?.(e, item)}
      className={`flex items-center gap-3 px-3 py-2 cursor-pointer transition-colors ${
        isActive
          ? "bg-[#419fd9] dark:bg-[#2b5278]"
          : "hover:bg-gray-100 dark:hover:bg-[#2b2b2b]"
      }`}
    >
      {/* Avatar */}
      {isSaved ? (
        <div className="w-[54px] h-[54px] rounded-full bg-[#6c9fd2] flex items-center justify-center shrink-0">
          <i className="fas fa-bookmark text-white text-xl" />
        </div>
      ) : (
        <Avatar src={item.avatar} name={item.username} size={54} online={item.online} />
      )}

      {/* Content */}
      <div className="flex-1 min-w-0 py-1 border-b border-gray-100 dark:border-gray-800">
        <div className="flex items-center justify-between">
          <span className={`font-semibold text-[15px] truncate ${isActive ? "text-white" : "text-gray-900 dark:text-white"}`}>
            {isSaved ? t("chat_saved_messages") : (item.full_name || item.username)}
          </span>
          <div className="flex items-center gap-2 shrink-0">
            {muted && <i className={`fas fa-volume-xmark text-xs ${isActive ? "text-white/70" : "text-gray-400"}`} />}
            {pinned && <i className={`fas fa-thumbtack text-xs ${isActive ? "text-white/70" : "text-gray-400"}`} />}
          {lastMessage?.created_at && (
            <span className={`text-xs shrink-0 ml-2 ${
              isActive ? "text-white/70" : unread > 0 ? "text-[#4fae4e]" : "text-gray-400"
            }`}>
              {formatChatListTime(lastMessage.created_at)}
            </span>
          )}
          </div>
        </div>

        <div className="flex items-center justify-between mt-0.5">
          <span className={`text-sm truncate ${
            isActive ? "text-white/80" : "text-gray-500 dark:text-gray-400"
          }`}>
            {typing ? (
              <span className={isActive ? "text-white/90" : "text-[#4fae4e]"}>{t("chat_typing")}</span>
            ) : lastMessage?.content?.startsWith("__CALL:") ? (
              <span>
                <i className={`fas ${lastMessage.content.includes("video") ? "fa-video" : "fa-phone"} mr-1 ${
                  lastMessage.content.includes("missed") ? "text-red-400" : "text-green-400"
                }`} />
                {lastMessage.content.includes("missed")
                  ? t("call_missed")
                  : (lastMessage.content.includes("video") ? t("call_video") : t("call_audio"))
                }
              </span>
            ) : locationPreview ? (
              <span><i className="fas fa-map-marker-alt mr-1" />{t("chat_location") || "Location"}</span>
            ) : lastMessage?.content ? (
              lastMessage.content.slice(0, 40)
            ) : lastMessage?.image ? (
              <span><i className="fas fa-image mr-1" />{t("chat_photo")}</span>
            ) : lastMessage?.audio ? (
              <span><i className="fas fa-microphone mr-1" />{t("chat_voice_message")}</span>
            ) : lastMessage?.video ? (
              <span><i className="fas fa-video mr-1" />{t("call_video")}</span>
            ) : (
              ""
            )}
          </span>
          {unread > 0 && (
            <span className={`text-white text-xs font-bold rounded-full min-w-[22px] h-[22px] flex items-center justify-center px-1.5 shrink-0 ${
              isActive ? "bg-white/30" : "bg-[#4fae4e]"
            }`}>
              {unread > 99 ? "99+" : unread}
            </span>
          )}
        </div>
      </div>
    </div>
  );
}
