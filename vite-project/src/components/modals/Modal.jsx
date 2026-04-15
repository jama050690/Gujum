import { useEffect } from "react";

export default function Modal({ isOpen, onClose, title, children, className = "" }) {
  useEffect(() => {
    const handleEscape = (e) => { if (e.key === "Escape") onClose(); };
    if (isOpen) document.addEventListener("keydown", handleEscape);
    return () => document.removeEventListener("keydown", handleEscape);
  }, [isOpen, onClose]);

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4" onClick={onClose}>
      <div className="absolute inset-0 bg-black/50 backdrop-blur-sm" />
      <div
        className={`relative bg-white dark:bg-[#1e1e3a] rounded-2xl shadow-2xl w-full max-w-md max-h-[90vh] flex flex-col animate-slideUp ${className}`}
        onClick={(e) => e.stopPropagation()}
      >
        {title && (
          <div className="flex items-center justify-between px-5 py-4 border-b border-gray-200 dark:border-gray-700 shrink-0">
            <h3 className="text-lg font-bold text-gray-900 dark:text-white">{title}</h3>
            <button onClick={onClose} className="p-1.5 text-gray-400 hover:text-gray-600 hover:bg-gray-100 dark:hover:bg-gray-800 rounded-lg">
              <i className="fas fa-times" />
            </button>
          </div>
        )}
        <div className="flex-1 min-h-0 overflow-y-auto">{children}</div>
      </div>
    </div>
  );
}
