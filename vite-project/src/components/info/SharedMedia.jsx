import { useState, useEffect } from "react";
import { useChat } from "@/context/ChatContext";
import { resolveMediaUrl } from "@/utils/media";
import { markMediaUnavailable, useMediaAvailability } from "@/hooks/useMediaAvailability";

function countMedia(messages) {
  let images = 0, files = 0, links = 0, audio = 0;
  const linkRegex = /https?:\/\/[^\s]+/g;

  messages.forEach((msg) => {
    if (msg.image) images++;
    if (msg.audio) audio++;
    if (msg.content) {
      const found = msg.content.match(linkRegex);
      if (found) links += found.length;
    }
  });

  return { images, files, links, audio };
}

function extractLinks(messages) {
  const linkRegex = /https?:\/\/[^\s]+/g;
  const results = [];
  messages.forEach((msg) => {
    if (msg.content) {
      const found = msg.content.match(linkRegex);
      if (found) {
        found.forEach((url) => {
          results.push({ url, date: msg.created_at, username: msg.username });
        });
      }
    }
  });
  return results;
}

function SharedImageItem({ src }) {
  const { isMissing, isChecking } = useMediaAvailability(src);
  const [loadError, setLoadError] = useState(false);

  if (isChecking) {
    return (
      <div className="flex aspect-square items-center justify-center rounded-md bg-gray-100 text-xs text-gray-400 dark:bg-gray-800 dark:text-gray-500">
        Tekshirilmoqda
      </div>
    );
  }

  if (isMissing || loadError) {
    return (
      <div className="flex aspect-square items-center justify-center rounded-md bg-gray-100 px-2 text-center text-xs text-gray-400 dark:bg-gray-800 dark:text-gray-500">
        Rasm yo'q
      </div>
    );
  }

  return (
    <img
      src={src}
      alt=""
      className="w-full aspect-square object-cover rounded-md cursor-pointer hover:opacity-80 transition-opacity"
      onClick={() => window.open(src, "_blank")}
      onError={() => {
        markMediaUnavailable(src);
        setLoadError(true);
      }}
    />
  );
}

function SharedAudioItem({ src }) {
  const { isMissing, isChecking } = useMediaAvailability(src);
  const [loadError, setLoadError] = useState(false);

  if (isChecking) {
    return (
      <div className="flex items-center gap-3 p-2 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-800">
        <div className="w-9 h-9 rounded-full bg-blue-50 dark:bg-blue-900/30 flex items-center justify-center shrink-0">
          <i className="fas fa-music text-blue-500 text-xs" />
        </div>
        <div className="text-sm text-gray-400">Audio tekshirilmoqda...</div>
      </div>
    );
  }

  if (isMissing || loadError) {
    return (
      <div className="flex items-center gap-3 p-2 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-800">
        <div className="w-9 h-9 rounded-full bg-blue-50 dark:bg-blue-900/30 flex items-center justify-center shrink-0">
          <i className="fas fa-exclamation-triangle text-blue-500 text-xs" />
        </div>
        <div className="text-sm text-gray-400">Audio mavjud emas yoki buzilgan</div>
      </div>
    );
  }

  return (
    <div className="flex items-center gap-3 p-2 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-800">
      <div className="w-9 h-9 rounded-full bg-blue-50 dark:bg-blue-900/30 flex items-center justify-center shrink-0">
        <i className="fas fa-play text-blue-500 text-xs" />
      </div>
      <audio
        controls
        preload="none"
        className="flex-1 h-8"
        style={{ minWidth: 0 }}
        onError={() => {
          markMediaUnavailable(src);
          setLoadError(true);
        }}
      >
        <source src={src} />
      </audio>
    </div>
  );
}

export default function SharedMedia() {
  const { messages } = useChat();
  const [tab, setTab] = useState(null);

  const counts = countMedia(messages);

  const tabs = [
    { id: "images", icon: "fa-image", label: "Rasmlar", count: counts.images },
    { id: "files", icon: "fa-file", label: "Fayllar", count: counts.files },
    { id: "links", icon: "fa-link", label: "Linklar", count: counts.links },
    { id: "audio", icon: "fa-microphone", label: "Audio", count: counts.audio },
  ];

  return (
    <div className="border-t border-gray-200 dark:border-gray-700 pt-4">
      {/* Summary row */}
      <div className="space-y-1 mb-3">
        {tabs.filter(t => t.count > 0).map((t) => (
          <button
            key={t.id}
            onClick={() => setTab(tab === t.id ? null : t.id)}
            className={`w-full flex items-center gap-3 px-4 py-2.5 rounded-lg transition-colors ${
              tab === t.id
                ? "bg-blue-50 dark:bg-blue-900/20 text-blue-500"
                : "text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-800"
            }`}
          >
            <i className={`fas ${t.icon} w-5 text-center text-gray-400`} />
            <span className="text-sm flex-1 text-left">{t.count} {t.label.toLowerCase()}</span>
            <i className={`fas fa-chevron-right text-xs text-gray-400 transition-transform ${tab === t.id ? "rotate-90" : ""}`} />
          </button>
        ))}
        {tabs.every(t => t.count === 0) && (
          <p className="text-sm text-gray-400 text-center py-3">Media yo'q</p>
        )}
      </div>

      {/* Expanded content */}
      {tab === "images" && (
        <div className="grid grid-cols-3 gap-1 px-2 pb-2">
          {messages.filter(m => m.image).map((m, i) => {
            const src = resolveMediaUrl(m.image);
            return (
              <SharedImageItem key={i} src={src} />
            );
          })}
        </div>
      )}

      {tab === "links" && (
        <div className="space-y-1 px-2 pb-2">
          {extractLinks(messages).map((link, i) => (
            <a
              key={i}
              href={link.url}
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center gap-3 p-2.5 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors"
            >
              <div className="w-9 h-9 rounded-lg bg-blue-50 dark:bg-blue-900/30 flex items-center justify-center shrink-0">
                <i className="fas fa-link text-blue-500 text-sm" />
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-sm text-blue-500 truncate">{link.url}</p>
                <p className="text-xs text-gray-400">{link.username}</p>
              </div>
            </a>
          ))}
        </div>
      )}

      {tab === "audio" && (
        <div className="space-y-2 px-2 pb-2">
          {messages.filter(m => m.audio).map((m, i) => {
            const src = resolveMediaUrl(m.audio);
            return <SharedAudioItem key={i} src={src} />;
          })}
        </div>
      )}
    </div>
  );
}
