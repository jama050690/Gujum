import { useRef, useEffect, useState, useCallback } from "react";
import MessageBubble from "./MessageBubble";
import TypingIndicator from "./TypingIndicator";
import ChatContextMenu from "./ChatContextMenu";

function getDateLabel(dateStr) {
  const d = new Date(dateStr);
  const today = new Date();
  const yesterday = new Date();
  yesterday.setDate(today.getDate() - 1);

  if (d.toDateString() === today.toDateString()) return "Bugun";
  if (d.toDateString() === yesterday.toDateString()) return "Kecha";

  const day = String(d.getDate()).padStart(2, "0");
  const month = String(d.getMonth() + 1).padStart(2, "0");
  return `${day}.${month}.${d.getFullYear()}`;
}

export default function MessageList({ messages, currentUser, typingUser, onReply, onCopy, onSave, onDelete, onForward, chatBg, searchQuery, allowDownload }) {
  const bottomRef = useRef(null);
  const [contextMenu, setContextMenu] = useState(null);
  const [selectedIds, setSelectedIds] = useState(new Set());
  const selectMode = selectedIds.size > 0;

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, typingUser]);

  const toggleSelect = useCallback((msg) => {
    const key = msg.id || msg.savedAt || msg.created_at;
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  }, []);

  const exitSelectMode = useCallback(() => {
    setSelectedIds(new Set());
  }, []);

  const handleDeleteSelected = useCallback(() => {
    const selected = messages.filter((m) => selectedIds.has(m.id || m.savedAt || m.created_at));
    selected.forEach((m) => onDelete?.(m));
    setSelectedIds(new Set());
  }, [messages, selectedIds, onDelete]);

  const handleCopySelected = useCallback(() => {
    const selected = messages.filter((m) => selectedIds.has(m.id || m.savedAt || m.created_at));
    const text = selected.map((m) => m.content || "").filter(Boolean).join("\n");
    if (text) navigator.clipboard.writeText(text);
    setSelectedIds(new Set());
  }, [messages, selectedIds]);

  const handleContextMenu = useCallback((e, msg) => {
    if (selectMode) {
      e.preventDefault();
      toggleSelect(msg);
      return;
    }

    const isMine = msg.username === currentUser;
    const items = [];

    items.push({
      id: "reply",
      label: "Reply",
      icon: "fa-reply",
      onClick: () => onReply?.(msg),
    });

    if (isMine) {
      items.push({
        id: "edit",
        label: "Edit",
        icon: "fa-pen",
        onClick: () => {},
      });
    }

    items.push({
      id: "pin",
      label: "Pin",
      icon: "fa-thumbtack",
      onClick: () => {},
    });

    if (msg.content) {
      items.push({
        id: "copy",
        label: "Copy Text",
        icon: "fa-copy",
        onClick: () => onCopy?.(msg),
      });
    }

    items.push({
      id: "forward",
      label: "Forward",
      icon: "fa-share",
      onClick: () => onForward?.(msg),
    });

    items.push({
      id: "delete",
      label: "Delete",
      icon: "fa-trash",
      danger: true,
      dividerTop: true,
      onClick: () => onDelete?.(msg),
    });

    items.push({
      id: "select",
      label: "Select",
      icon: "fa-check-circle",
      onClick: () => toggleSelect(msg),
    });

    const menuWidth = 260;
    const menuHeight = items.length * 44 + 20;
    const mx = Math.min(e.clientX, window.innerWidth - menuWidth - 12);
    const my = Math.min(e.clientY, window.innerHeight - menuHeight - 12);
    setContextMenu({ x: mx, y: my, items });
  }, [currentUser, onReply, onCopy, onSave, onDelete, onForward, selectMode, toggleSelect]);

  let lastDate = null;

  return (
    <div className="flex-1 min-h-0 overflow-y-auto relative">
      {/* Select mode toolbar */}
      {selectMode && (
        <div className="sticky top-0 z-30 flex items-center justify-between px-4 py-2 bg-white dark:bg-[#242f3d] border-b border-gray-200 dark:border-gray-700 shadow-sm">
          <div className="flex items-center gap-3">
            <button onClick={exitSelectMode} className="w-8 h-8 flex items-center justify-center text-gray-500 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-full">
              <i className="fas fa-times" />
            </button>
            <span className="text-sm font-medium text-gray-700 dark:text-gray-200">{selectedIds.size} tanlandi</span>
          </div>
          <div className="flex items-center gap-1">
            <button onClick={handleCopySelected} className="w-9 h-9 flex items-center justify-center text-gray-500 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-full" title="Copy">
              <i className="fas fa-copy text-sm" />
            </button>
            <button onClick={handleDeleteSelected} className="w-9 h-9 flex items-center justify-center text-red-500 hover:bg-red-50 dark:hover:bg-red-900/20 rounded-full" title="Delete">
              <i className="fas fa-trash text-sm" />
            </button>
          </div>
        </div>
      )}

      <div
        className="px-4 py-3 tg-chat-bg min-h-full"
        style={chatBg ? { backgroundColor: chatBg } : undefined}
      >
        {messages.length === 0 && (
          <div className="flex flex-col items-center justify-center h-full text-gray-400">
            <i className="fas fa-comments text-5xl mb-3 opacity-30" />
            <p className="text-sm">Hali xabar yo'q. Birinchi bo'lib yozing!</p>
          </div>
        )}

        {messages.map((msg, idx) => {
          const msgDate = msg.created_at ? new Date(msg.created_at).toDateString() : null;
          let showDate = false;
          if (msgDate && msgDate !== lastDate) {
            showDate = true;
            lastDate = msgDate;
          }

          const msgKey = msg.id || msg.savedAt || msg.created_at;
          const isSelected = selectedIds.has(msgKey);

          return (
            <div
              key={msg.id ? `msg-${msg.id}` : `idx-${idx}`}
              onClick={selectMode ? () => toggleSelect(msg) : undefined}
              className={`${selectMode ? "cursor-pointer" : ""} ${isSelected ? "bg-[#419fd9]/15 dark:bg-[#419fd9]/20 -mx-4 px-4 rounded" : ""}`}
            >
              {showDate && (
                <div className="flex justify-center my-3">
                  <span className="bg-[#a0d0eb]/60 dark:bg-[#2b5278]/80 text-white text-xs font-medium px-3 py-1 rounded-full shadow-sm">
                    {getDateLabel(msg.created_at)}
                  </span>
                </div>
              )}
              <div className="flex items-center gap-2">
                {selectMode && (
                  <div className={`w-5 h-5 rounded-full border-2 flex items-center justify-center shrink-0 transition-colors ${
                    isSelected ? "bg-[#419fd9] border-[#419fd9]" : "border-gray-300 dark:border-gray-600"
                  }`}>
                    {isSelected && <i className="fas fa-check text-white text-[10px]" />}
                  </div>
                )}
                <div className="flex-1 min-w-0">
                  <MessageBubble
                    message={msg}
                    isMine={msg.username === currentUser}
                    onContextMenu={handleContextMenu}
                    searchQuery={searchQuery}
                    allowDownload={allowDownload}
                  />
                </div>
              </div>
            </div>
          );
        })}

        <TypingIndicator username={typingUser} />
        <div ref={bottomRef} />
      </div>

      {contextMenu && (
        <ChatContextMenu
          x={contextMenu.x}
          y={contextMenu.y}
          items={contextMenu.items}
          onClose={() => setContextMenu(null)}
        />
      )}
    </div>
  );
}
