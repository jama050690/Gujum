import UserInfo from "./UserInfo";
import GroupInfo from "./GroupInfo";
import ChannelInfo from "./ChannelInfo";
import SavedMessagesInfo from "./SavedMessagesInfo";

export default function InfoPanel({ chat, isOnline, onClose, onOpenSidebar, onAddMember, onDelete }) {
  if (!chat) return null;

  const isGroup = chat.type === "group";
  const isChannel = chat.type === "channel";
  const isSaved = chat.username === "__SAVED_MESSAGES__";

  return (
    <div className="w-full md:w-80 h-full bg-white dark:bg-[#1a1a2e] border-l border-gray-200 dark:border-gray-700 flex flex-col overflow-hidden">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 border-b border-gray-200 dark:border-gray-700 shrink-0">
        <h3 className="font-semibold text-gray-900 dark:text-white">Ma'lumot</h3>
        <button
          onClick={onClose}
          className="p-2 text-gray-500 hover:bg-gray-100 dark:hover:bg-gray-800 rounded-lg"
        >
          <i className="fas fa-times" />
        </button>
      </div>

      <div className="flex-1 overflow-y-auto">
        {isSaved ? (
          <SavedMessagesInfo />
        ) : isGroup ? (
          <GroupInfo group={chat} onAddMember={onAddMember} onDelete={onDelete} />
        ) : isChannel ? (
          <ChannelInfo channel={chat} onAddMember={onAddMember} onDelete={onDelete} />
        ) : (
          <UserInfo user={chat} isOnline={isOnline} />
        )}
      </div>
    </div>
  );
}
