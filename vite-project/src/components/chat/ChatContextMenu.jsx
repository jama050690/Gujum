import { useEffect, useRef } from "react";
import { createPortal } from "react-dom";

export default function ChatContextMenu({ x, y, items, onClose }) {
  const menuRef = useRef(null);

  useEffect(() => {
    const handleClick = (e) => {
      if (!menuRef.current) return;
      if (!menuRef.current.contains(e.target)) onClose();
    };
    const handleEsc = (e) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("mousedown", handleClick);
    window.addEventListener("keydown", handleEsc);
    return () => {
      window.removeEventListener("mousedown", handleClick);
      window.removeEventListener("keydown", handleEsc);
    };
  }, [onClose]);

  // Ekran chetiga chiqib ketmasligi uchun pozitsiya tuzatish
  const menuWidth = 250;
  const menuHeight = items.length * 44 + 10;
  const left = Math.min(x, window.innerWidth - menuWidth - 8);
  const top = Math.min(y, window.innerHeight - menuHeight - 8);

  return createPortal(
    <div
      ref={menuRef}
      className="fixed z-[1200] min-w-[250px] rounded-xl bg-white dark:bg-[#2c2c2c] shadow-2xl border border-gray-200 dark:border-gray-700 py-1"
      style={{ left, top }}
    >
      {items.map((item) => (
        <button
          key={item.id}
          type="button"
          onClick={() => {
            item.onClick?.();
            onClose();
          }}
          className={`w-full flex items-center gap-3 px-4 py-2.5 text-left transition-colors ${
            item.danger
              ? "text-red-500 hover:bg-red-50 dark:hover:bg-red-900/20"
              : "text-gray-900 dark:text-white hover:bg-gray-100 dark:hover:bg-white/10"
          } ${item.dividerTop ? "border-t border-gray-200 dark:border-gray-700 mt-1 pt-3" : ""}`}
        >
          <i className={`fas ${item.icon} w-5 text-center ${item.danger ? "text-red-500" : "text-gray-500 dark:text-gray-300"}`} />
          <span className="text-[15px]">{item.label}</span>
        </button>
      ))}
    </div>,
    document.body
  );
}
