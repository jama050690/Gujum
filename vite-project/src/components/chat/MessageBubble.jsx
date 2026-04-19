import { useEffect, useRef, useState } from "react";
import { formatTimestamp, formatCallDuration } from "@/utils/formatters";
import Avatar from "@/components/common/Avatar";
import { useLanguage } from "@/context/LanguageContext";
import { parseLocationMessage } from "@/utils/location";
import { resolveMediaUrl } from "@/utils/media";
import { markMediaUnavailable, useMediaAvailability } from "@/hooks/useMediaAvailability";

function highlightText(text, query) {
  if (!query || !text) return text;
  const q = query.toLowerCase();
  const idx = text.toLowerCase().indexOf(q);
  if (idx === -1) return text;
  return (
    <>
      {text.slice(0, idx)}
      <mark className="bg-yellow-300 dark:bg-yellow-600 rounded px-0.5">
        {text.slice(idx, idx + query.length)}
      </mark>
      {text.slice(idx + query.length)}
    </>
  );
}

const VIDEO_EXTS = [".mp4", ".mov", ".avi", ".webm", ".mkv", ".3gp"];
const IMAGE_EXTS = [".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".svg", ".heic", ".heif", ".avif"];

function isVideoFile(path) {
  if (!path) return false;
  const ext = path.split("?")[0].split(".").pop()?.toLowerCase();
  return VIDEO_EXTS.includes(`.${ext}`);
}

function isImageFile(path) {
  if (!path) return false;
  if (/^data:image\//i.test(path)) return true;
  const ext = path.split("?")[0].split(".").pop()?.toLowerCase();
  return IMAGE_EXTS.includes(`.${ext}`);
}

function fileNameFromPath(path = "") {
  return path.split("/").pop() || path;
}

const CALL_REGEX = /^__CALL:(audio|video):(missed|\d+)__$/;

function parseCallMessage(content) {
  if (!content) return null;
  const match = content.match(CALL_REGEX);
  if (!match) return null;
  return {
    type: match[1],
    isMissed: match[2] === "missed",
    duration: match[2] === "missed" ? 0 : parseInt(match[2], 10),
  };
}

function formatAudioTime(value) {
  if (!Number.isFinite(value) || value < 0) return "0:00";
  const total = Math.floor(value);
  const minutes = Math.floor(total / 60);
  const seconds = String(total % 60).padStart(2, "0");
  return `${minutes}:${seconds}`;
}

function InlineAudioPlayer({ src, isMine }) {
  const audioRef = useRef(null);
  const [playing, setPlaying] = useState(false);
  const [muted, setMuted] = useState(false);
  const [duration, setDuration] = useState(0);
  const [current, setCurrent] = useState(0);
  const [loadError, setLoadError] = useState(false);
  const { isAvailable, isMissing, isChecking } = useMediaAvailability(src);

  useEffect(() => {
    const audio = audioRef.current;
    if (!audio || !isAvailable) return undefined;

    const handleLoaded = () => setDuration(audio.duration || 0);
    const handleTime = () => setCurrent(audio.currentTime || 0);
    const handleEnded = () => setPlaying(false);

    audio.addEventListener("loadedmetadata", handleLoaded);
    audio.addEventListener("timeupdate", handleTime);
    audio.addEventListener("ended", handleEnded);
    return () => {
      audio.removeEventListener("loadedmetadata", handleLoaded);
      audio.removeEventListener("timeupdate", handleTime);
      audio.removeEventListener("ended", handleEnded);
    };
  }, [src, isAvailable]);

  useEffect(() => {
    const audio = audioRef.current;
    if (!audio || !isAvailable) return;
    setPlaying(false);
    setCurrent(0);
    setDuration(0);
    setLoadError(false);
    audio.load();
  }, [src, isAvailable]);

  if (isChecking) {
    return (
      <div
        className={`mt-1 rounded-2xl px-3 py-2 text-sm ${
          isMine
            ? "bg-white/90 text-gray-500 dark:bg-[#1f2b3a] dark:text-gray-300"
            : "bg-[#f6f7fb] text-gray-500 dark:bg-[#243140] dark:text-gray-300"
        }`}
      >
        Audio tekshirilmoqda...
      </div>
    );
  }

  if (isMissing || loadError) {
    return (
      <div
        className={`mt-1 rounded-2xl px-3 py-2 text-sm ${
          isMine
            ? "bg-white/90 text-gray-700 dark:bg-[#1f2b3a] dark:text-gray-200"
            : "bg-[#f6f7fb] text-gray-700 dark:bg-[#243140] dark:text-gray-200"
        }`}
      >
        Audio fayli mavjud emas yoki buzilgan.
      </div>
    );
  }

  const togglePlay = async () => {
    const audio = audioRef.current;
    if (!audio) return;
    if (playing) {
      audio.pause();
      setPlaying(false);
      return;
    }
    try {
      await audio.play();
      setPlaying(true);
    } catch {
      setPlaying(false);
    }
  };

  const toggleMute = () => {
    const audio = audioRef.current;
    if (!audio) return;
    const next = !muted;
    audio.muted = next;
    setMuted(next);
  };

  const handleSeek = (e) => {
    const audio = audioRef.current;
    if (!audio || !duration) return;
    const rect = e.currentTarget.getBoundingClientRect();
    const pct = Math.min(Math.max(0, (e.clientX - rect.left) / rect.width), 1);
    const target = pct * duration;
    audio.currentTime = target;
    setCurrent(target);
  };

  const progress = duration > 0 ? (current / duration) * 100 : 0;
  const timeText = `${formatAudioTime(current)} / ${formatAudioTime(duration)}`;

  return (
    <div
      className={`mt-1 flex items-center gap-2 rounded-full px-3 py-2 w-[260px] max-w-full shadow-sm ${
        isMine
          ? "bg-white/90 dark:bg-[#1f2b3a]"
          : "bg-[#f6f7fb] dark:bg-[#243140]"
      }`}
    >
      <button
        type="button"
        onClick={togglePlay}
        className="w-9 h-9 rounded-full bg-[#3a8bcd]/20 flex items-center justify-center text-[#3a8bcd]"
      >
        <i className={`fas ${playing ? "fa-pause" : "fa-play"} text-xs`} />
      </button>
      <span className="text-[11px] text-gray-600 dark:text-gray-300 w-[70px] text-center">
        {timeText}
      </span>
      <div
        className="flex-1 h-1.5 rounded-full bg-black/10 dark:bg-white/10 cursor-pointer"
        onClick={handleSeek}
      >
        <div
          className="h-full rounded-full bg-[#3a8bcd]"
          style={{ width: `${progress}%` }}
        />
      </div>
      <button
        type="button"
        onClick={toggleMute}
        className="text-gray-500 hover:text-gray-700 dark:text-gray-300 dark:hover:text-white"
      >
        <i className={`fas ${muted ? "fa-volume-mute" : "fa-volume-up"}`} />
      </button>
      <button
        type="button"
        className="text-gray-400 hover:text-gray-600 dark:text-gray-400 dark:hover:text-white"
      >
        <i className="fas fa-ellipsis-v" />
      </button>
      <audio
        ref={audioRef}
        src={src}
        preload="none"
        onError={() => {
          setPlaying(false);
          markMediaUnavailable(src);
          setLoadError(true);
        }}
      />
    </div>
  );
}

function InlineVideoPreview({ src, onOpen }) {
  const [loadError, setLoadError] = useState(false);
  const { isMissing, isChecking } = useMediaAvailability(src);

  if (isChecking) {
    return (
      <div className="mt-1 rounded-2xl bg-black/5 px-4 py-6 text-center text-sm text-gray-500 shadow-sm dark:bg-white/5 dark:text-gray-300">
        Video tekshirilmoqda...
      </div>
    );
  }

  if (isMissing || loadError) {
    return (
      <div className="mt-1 rounded-2xl bg-black/5 px-4 py-6 text-center text-sm text-gray-500 shadow-sm dark:bg-white/5 dark:text-gray-300">
        Video fayli mavjud emas yoki buzilgan.
      </div>
    );
  }

  return (
    <div
      className="relative mt-1 rounded-2xl overflow-hidden bg-black/10 dark:bg-black/40 cursor-pointer shadow-sm"
      onClick={onOpen}
      role="button"
      tabIndex={0}
      onKeyDown={(e) => {
        if (e.key === "Enter") onOpen?.();
      }}
    >
      <video
        src={src}
        muted
        playsInline
        preload="metadata"
        className="w-full max-h-80 object-cover"
        onError={() => {
          markMediaUnavailable(src);
          setLoadError(true);
        }}
      />
      <div className="absolute inset-0 bg-gradient-to-b from-black/10 via-transparent to-black/30" />
      <div className="absolute left-3 bottom-3 flex items-center gap-2">
        <div className="w-9 h-9 rounded-full bg-black/60 flex items-center justify-center">
          <i className="fas fa-play text-white text-xs" />
        </div>
        <div className="h-1.5 w-24 rounded-full bg-white/40">
          <div className="h-1.5 w-10 rounded-full bg-white/80" />
        </div>
      </div>
      <div className="absolute right-3 bottom-3 w-8 h-8 rounded-full bg-black/60 flex items-center justify-center">
        <i className="fas fa-ellipsis-v text-white text-xs" />
      </div>
    </div>
  );
}

function InlineImagePreview({ src, onOpen }) {
  const [loadError, setLoadError] = useState(false);
  const { isAvailable, isMissing, isChecking } = useMediaAvailability(src);

  if (isChecking) {
    return (
      <div className="rounded-2xl bg-black/5 px-4 py-6 text-center text-sm text-gray-500 shadow-sm dark:bg-white/5 dark:text-gray-300">
        Rasm tekshirilmoqda...
      </div>
    );
  }

  if (isMissing || loadError) {
    return (
      <div className="rounded-2xl bg-black/5 px-4 py-6 text-center text-sm text-gray-500 shadow-sm dark:bg-white/5 dark:text-gray-300">
        Rasm fayli mavjud emas yoki buzilgan.
      </div>
    );
  }

  return (
    <img
      src={src}
      alt="Rasm"
      className="max-w-full rounded-2xl cursor-pointer max-h-96 object-cover shadow-sm"
      onClick={onOpen}
      onError={() => {
        markMediaUnavailable(src);
        setLoadError(true);
      }}
    />
  );
}

function MediaTimeBadge({ timestamp, isMine, read }) {
  return (
    <div className="absolute bottom-2 right-2 rounded-full bg-black/50 px-2 py-0.5 text-[11px] text-white flex items-center gap-1">
      <span>{timestamp}</span>
      {isMine && (
        <i
          className={`fas ${read ? "fa-check-double" : "fa-check"} text-[10px] text-[#6db870]`}
        />
      )}
    </div>
  );
}

function FileAttachment({ src, label, isMine }) {
  return (
    <a
      href={src}
      target="_blank"
      rel="noreferrer"
      className={`mt-1 inline-flex max-w-full items-center gap-2 rounded-[14px] px-3 py-2 transition-colors ${
        isMine
          ? "bg-black/10 text-gray-900 hover:bg-black/15 dark:bg-black/20 dark:text-white dark:hover:bg-black/30"
          : "bg-black/10 text-gray-900 hover:bg-black/15 dark:bg-black/20 dark:text-white dark:hover:bg-black/30"
      }`}
    >
      <i className="far fa-file-lines shrink-0 text-[18px] text-[#3a8bcd]" />
      <div className="min-w-0 max-w-[180px]">
        <div className="truncate text-sm">{label}</div>
      </div>
    </a>
  );
}

export default function MessageBubble({
  message,
  isMine,
  onContextMenu,
  searchQuery,
  allowDownload = true,
}) {
  const { t } = useLanguage();
  const callInfo = parseCallMessage(message.content);
  const locationInfo = parseLocationMessage(message.content);
  const [viewer, setViewer] = useState(null);

  // Check for video field first (new), then image field (legacy/images)
  const videoSrc = message.video ? resolveMediaUrl(message.video) : null;

  const imageSrc =
    message.image && isImageFile(message.image)
      ? resolveMediaUrl(message.image)
      : null;

  const isVideo = !!videoSrc || isVideoFile(message.image);
  const mediaSrc =
    videoSrc ||
    (isVideoFile(message.image)
      ? resolveMediaUrl(message.image)
      : imageSrc);

  const audioSrc = message.audio ? resolveMediaUrl(message.audio) : null;
  const documentSrc =
    message.image && !isVideoFile(message.image) && !isImageFile(message.image)
      ? resolveMediaUrl(message.image)
      : null;

  useEffect(() => {
    if (!viewer) return undefined;
    const handleKey = (event) => {
      if (event.key === "Escape") {
        setViewer(null);
      }
    };
    window.addEventListener("keydown", handleKey);
    return () => window.removeEventListener("keydown", handleKey);
  }, [viewer]);

  const handleContextMenu = (e) => {
    e.preventDefault();
    onContextMenu?.(e, message);
  };
  const hasTextContent = message.content && !locationInfo;
  const showMediaOverlay =
    mediaSrc && !hasTextContent && !locationInfo && !audioSrc && !documentSrc;
  const timeLabel = formatTimestamp(message.created_at);

  // Call message — Telegram style
  if (callInfo) {
    return (
      <div className="flex justify-center my-2">
        <div className="flex items-center gap-2 bg-white/80 dark:bg-[#212121]/80 px-4 py-2 rounded-xl shadow-sm">
          <i
            className={`fas ${callInfo.type === "video" ? "fa-video" : "fa-phone"} ${
              callInfo.isMissed ? "text-red-500" : "text-green-500"
            }`}
          />
          <div className="text-sm">
            <span
              className={
                callInfo.isMissed
                  ? "text-red-500 font-medium"
                  : "text-gray-800 dark:text-white font-medium"
              }
            >
              {callInfo.isMissed
                ? isMine
                  ? "Javobsiz qo'ng'iroq"
                  : "O'tkazib yuborilgan qo'ng'iroq"
                : callInfo.type === "video"
                  ? "Video qo'ng'iroq"
                  : "Qo'ng'iroq"}
            </span>
            {!callInfo.isMissed && callInfo.duration > 0 && (
              <span className="text-gray-400 ml-1">
                ({formatCallDuration(callInfo.duration)})
              </span>
            )}
          </div>
          <span className="text-[11px] text-gray-400 ml-1">
            {formatTimestamp(message.created_at)}
          </span>
        </div>
      </div>
    );
  }

  return (
    <div
      className={`flex gap-2 mb-1 ${isMine ? "justify-end" : "justify-start"} group`}
    >
      {!isMine && (
        <Avatar
          src={message.avatar}
          name={message.username}
          size={34}
          className="mt-auto shrink-0"
        />
      )}

      <div
        className={`relative max-w-[70%] ${isMine ? "msg-bubble-out" : "msg-bubble-in"}`}
        onContextMenu={handleContextMenu}
      >
        {/* Bubble */}
        <div
          className={`rounded-lg px-3 py-1.5 shadow-sm ${
            isMine
              ? "bg-[#effdde] dark:bg-[#2b5c3a] text-gray-900 dark:text-white rounded-tr-none"
              : "bg-white dark:bg-[#212121] text-gray-900 dark:text-white rounded-tl-none"
          }`}
        >
          {!isMine && (
            <p className="text-xs font-semibold text-[#3a8bcd] mb-0.5">
              {message.full_name || message.username}
            </p>
          )}

          {/* Reply quote */}
          {message.reply_to_username && (
            <div
              className={`flex gap-1.5 mb-1 px-2 py-1 rounded ${
                isMine
                  ? "bg-[#d4f5c4] dark:bg-[#245a32]"
                  : "bg-gray-100 dark:bg-[#2a2a2a]"
              }`}
            >
              <div className="w-0.5 rounded-full bg-[#3a8bcd] shrink-0" />
              <div className="min-w-0">
                <p className="text-xs font-semibold text-[#3a8bcd]">
                  {message.reply_to_username}
                </p>
                <p className="text-xs text-gray-500 dark:text-gray-400 truncate">
                  {message.reply_to_content || "..."}
                </p>
              </div>
            </div>
          )}

          {mediaSrc && isVideo && (
            <div className="relative">
              <InlineVideoPreview
                src={mediaSrc}
                onOpen={() => setViewer({ type: "video", src: mediaSrc })}
              />
              {showMediaOverlay && (
                <MediaTimeBadge
                  timestamp={timeLabel}
                  isMine={isMine}
                  read={message.read}
                />
              )}
            </div>
          )}

          {mediaSrc && !isVideo && (
            <div className="relative mt-1">
              <InlineImagePreview
                src={mediaSrc}
                onOpen={() => setViewer({ type: "image", src: mediaSrc })}
              />
              {showMediaOverlay && (
                <MediaTimeBadge
                  timestamp={timeLabel}
                  isMine={isMine}
                  read={message.read}
                />
              )}
            </div>
          )}

          {documentSrc && (
            <FileAttachment
              src={documentSrc}
              label={fileNameFromPath(message.image)}
              isMine={isMine}
            />
          )}

          {locationInfo && (
            <button
              type="button"
              onClick={() =>
                window.open(
                  `https://www.google.com/maps?q=${locationInfo.lat},${locationInfo.lng}`,
                  "_blank"
                )
              }
              className={`mt-1 w-full rounded-lg px-3 py-2 text-left transition-colors ${
                isMine
                  ? "bg-[#d4f5c4] dark:bg-[#245a32]"
                  : "bg-gray-100 dark:bg-[#2a2a2a]"
              }`}
            >
              <div className="flex items-center gap-2">
                <i className="fas fa-map-marker-alt text-[#3a8bcd]" />
                <div className="flex-1 min-w-0">
                  <div className="text-sm font-semibold">
                    {t("chat_location") || "Location"}
                  </div>
                  <div className="text-xs text-gray-500 dark:text-gray-400 truncate">
                    {locationInfo.lat.toFixed(5)}, {locationInfo.lng.toFixed(5)}
                  </div>
                </div>
              </div>
            </button>
          )}

          {hasTextContent && (
            <p
              className={`text-[14px] leading-relaxed whitespace-pre-wrap break-words ${mediaSrc ? "mt-1" : ""}`}
            >
              {searchQuery
                ? highlightText(message.content, searchQuery)
                : message.content}
            </p>
          )}

          {audioSrc && (
            <InlineAudioPlayer src={audioSrc} isMine={isMine} />
          )}

          {/* Time + checkmarks */}
          <div
            className={`flex items-center gap-1 justify-end -mb-0.5 ${
              showMediaOverlay
                ? "mt-0 hidden"
                : hasTextContent || locationInfo || documentSrc
                  ? "mt-0"
                  : "mt-1"
            }`}
          >
            <span
              className={`text-[11px] ${isMine ? "text-[#6db870] dark:text-[#6aad6a]" : "text-gray-400"}`}
            >
              {formatTimestamp(message.created_at)}
            </span>
            {isMine && (
              <i
                className={`fas ${message.read ? "fa-check-double" : "fa-check"} text-[11px] text-[#6db870] dark:text-[#6aad6a]`}
              />
            )}
          </div>
        </div>
      </div>

      {viewer && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 px-4"
          role="dialog"
          aria-modal="true"
          onClick={() => setViewer(null)}
        >
          <div
            className="relative w-full max-w-3xl"
            onClick={(event) => event.stopPropagation()}
          >
            <button
              type="button"
              className="absolute -top-10 right-0 text-white/80 hover:text-white"
              onClick={() => setViewer(null)}
            >
              <i className="fas fa-times" />
            </button>
            {viewer.type === "image" ? (
              <img
                src={viewer.src}
                alt="Media"
                className="w-full max-h-[80vh] object-contain rounded-xl bg-black"
              />
            ) : (
              <video
                src={viewer.src}
                className="w-full max-h-[80vh] rounded-xl bg-black"
                controls
                autoPlay
              />
            )}
          </div>
        </div>
      )}
    </div>
  );
}
