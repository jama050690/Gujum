import { useState, useRef, useEffect } from "react";
import { uploadFile } from "@/utils/api";
import { useLanguage } from "@/context/LanguageContext";
import { encodeLocation } from "@/utils/location";
import EmojiPicker from "emoji-picker-react";

const AUDIO_ACCEPT =
  "audio/*,.mp3,.m4a,.aac,.wav,.ogg,.opus,.amr,.flac,.webm";
const DOCUMENT_ACCEPT =
  ".pdf,.doc,.docx,.xls,.xlsx,.ppt,.pptx,.txt,.rtf,.csv,.zip,.rar,.7z,.json,.xml,.md";

function isHoverCapablePointer() {
  if (typeof window === "undefined" || typeof window.matchMedia !== "function") {
    return false;
  }
  return window.matchMedia("(hover: hover) and (pointer: fine)").matches;
}

export default function MessageInput({
  onSend,
  onTyping,
  disabled,
  replyTo,
  onCancelReply,
}) {
  const { t } = useLanguage();
  const tr = (key, fallback) => {
    const value = t(key);
    return value === key ? fallback : value;
  };
  const [text, setText] = useState("");
  const [recording, setRecording] = useState(false);
  const [showEmoji, setShowEmoji] = useState(false);
  const [showAttachMenu, setShowAttachMenu] = useState(false);
  const [pendingFile, setPendingFile] = useState(null); // { file, previewUrl, kind }
  const [uploading, setUploading] = useState(false);
  const [locating, setLocating] = useState(false);
  const [hoverMenuEnabled, setHoverMenuEnabled] = useState(false);
  const mediaRecorderRef = useRef(null);
  const chunksRef = useRef([]);
  const attachMenuTimerRef = useRef(null);
  const photoInputRef = useRef(null);
  const videoInputRef = useRef(null);
  const documentInputRef = useRef(null);
  const audioInputRef = useRef(null);
  const emojiRef = useRef(null);
  const attachMenuRef = useRef(null);
  const textareaRef = useRef(null);

  useEffect(() => {
    setHoverMenuEnabled(isHoverCapablePointer());
  }, []);

  // Close floating popups on outside click
  useEffect(() => {
    const handleClickOutside = (e) => {
      if (emojiRef.current && !emojiRef.current.contains(e.target)) {
        setShowEmoji(false);
      }
      if (attachMenuRef.current && !attachMenuRef.current.contains(e.target)) {
        setShowAttachMenu(false);
      }
    };
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  // Cleanup preview URL on unmount or change
  useEffect(() => {
    return () => {
      if (attachMenuTimerRef.current) {
        window.clearTimeout(attachMenuTimerRef.current);
      }
      if (pendingFile?.previewUrl) URL.revokeObjectURL(pendingFile.previewUrl);
    };
  }, [pendingFile]);

  // Type without focusing the input first (desktop-like behavior)
  useEffect(() => {
    const isEditableTarget = (el) => {
      if (!el) return false;
      const tag = el.tagName;
      return tag === "INPUT" || tag === "TEXTAREA" || el.isContentEditable;
    };

    const handleGlobalKeyDown = (e) => {
      if (disabled) return;
      if (isEditableTarget(e.target)) return;
      if (e.ctrlKey || e.metaKey || e.altKey) return;

      if (e.key === "Enter") {
        e.preventDefault();
        if (pendingFile) {
          handleSendWithFile();
        } else {
          const value = text.trim();
          if (value) {
            onSend({ message: value });
            setText("");
          }
        }
      } else if (e.key === "Escape" && pendingFile) {
        cancelPendingFile();
      } else if (e.key.length === 1) {
        e.preventDefault();
        setText((prev) => prev + e.key);
        onTyping?.();
      } else if (e.key === "Backspace") {
        e.preventDefault();
        setText((prev) => prev.slice(0, -1));
      }
    };

    window.addEventListener("keydown", handleGlobalKeyDown);
    return () => window.removeEventListener("keydown", handleGlobalKeyDown);
  }, [disabled, onTyping, onSend, text, pendingFile]);

  const onEmojiClick = (emojiData) => {
    setText((prev) => prev + emojiData.emoji);
    textareaRef.current?.focus();
  };

  const handleSend = () => {
    if (pendingFile) {
      handleSendWithFile();
      return;
    }
    if (!text.trim() && !disabled) return;
    onSend({ message: text.trim() });
    setText("");
  };

  const handleSendWithFile = async () => {
    if (!pendingFile || uploading) return;
    setUploading(true);
    try {
      const isVideo = pendingFile.kind === "video";
      const endpoint = isVideo ? "/api/upload-video" : "/api/upload";
      const fieldName = isVideo ? "video" : "image";

      const formData = new FormData();
      formData.append(fieldName, pendingFile.file);
      const data = await uploadFile(endpoint, formData);

      const payload = { message: text.trim() };
      if (isVideo) {
        payload.video = data.path;
      } else if (pendingFile.kind === "document" || pendingFile.kind === "image") {
        payload.image = data.path;
      }
      onSend(payload);
      setText("");
      cancelPendingFile();
    } catch (err) {
      console.error("Fayl yuklashda xato:", err);
    } finally {
      setUploading(false);
    }
  };

  const cancelPendingFile = () => {
    if (pendingFile?.previewUrl) URL.revokeObjectURL(pendingFile.previewUrl);
    setPendingFile(null);
  };

  const handleKeyDown = (e) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
    onTyping?.();
  };

  const createPendingFile = (file, kind) => {
    if (!file) return;
    const previewUrl =
      kind === "document" ? null : URL.createObjectURL(file);
    setPendingFile({ file, previewUrl, kind });
    setShowAttachMenu(false);
    textareaRef.current?.focus();
  };

  const handleImageSelect = (e) => {
    const file = e.target.files[0];
    e.target.value = "";
    if (!file) return;
    createPendingFile(file, "image");
  };

  const handleVideoSelect = (e) => {
    const file = e.target.files[0];
    e.target.value = "";
    if (!file) return;
    if (file.size > 800 * 1024 * 1024) {
      alert(tr("video_too_large", "Video hajmi 800MB dan oshmasligi kerak"));
      return;
    }
    createPendingFile(file, "video");
  };

  const handleDocumentSelect = (e) => {
    const file = e.target.files[0];
    e.target.value = "";
    if (!file) return;
    createPendingFile(file, "document");
  };

  const handleAudioFileSelect = async (e) => {
    const file = e.target.files?.[0];
    e.target.value = "";
    setShowAttachMenu(false);
    if (!file || uploading) return;

    setUploading(true);
    try {
      const formData = new FormData();
      formData.append("audio", file);
      const data = await uploadFile("/api/upload-audio", formData);
      onSend({
        message: text.trim(),
        audio: data.path,
      });
      setText("");
    } catch (err) {
      console.error("Audio fayl yuklashda xato:", err);
    } finally {
      setUploading(false);
    }
  };

  const handleSendLocation = () => {
    if (disabled) return;
    if (locating) return;
    if (!navigator.geolocation) {
      alert(t("chat_location_unavailable") || "Location is not supported");
      setShowAttachMenu(false);
      return;
    }

    setLocating(true);
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        const { latitude, longitude } = pos.coords || {};
        const payload = encodeLocation(latitude, longitude);
        if (payload) {
          onSend({ message: payload });
          setText("");
        } else {
          alert(t("chat_location_failed") || "Could not get location");
        }
        setShowAttachMenu(false);
        setLocating(false);
        textareaRef.current?.focus();
      },
      (err) => {
        console.error("Location error:", err);
        const denied =
          err && (err.code === 1 || err.PERMISSION_DENIED === 1);
        alert(
          denied
            ? t("chat_location_permission_denied") ||
                "Location permission was denied"
            : t("chat_location_failed") || "Could not get location"
        );
        setShowAttachMenu(false);
        setLocating(false);
      },
      { enableHighAccuracy: true, timeout: 10000, maximumAge: 0 }
    );
  };

  const toggleRecording = async () => {
    if (recording) {
      mediaRecorderRef.current?.stop();
      setRecording(false);
      return;
    }

    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const mediaRecorder = new MediaRecorder(stream);
      mediaRecorderRef.current = mediaRecorder;
      chunksRef.current = [];

      mediaRecorder.ondataavailable = (e) => chunksRef.current.push(e.data);
      mediaRecorder.onstop = async () => {
        const blob = new Blob(chunksRef.current, { type: "audio/webm" });
        stream.getTracks().forEach((t) => t.stop());

        const formData = new FormData();
        formData.append("audio", blob, `audio_${Date.now()}.webm`);

        try {
          const data = await uploadFile("/api/upload-audio", formData);
          onSend({ audio: data.path });
        } catch (err) {
          console.error("Audio yuklashda xato:", err);
        }
      };

      mediaRecorder.start();
      setRecording(true);
    } catch (err) {
      console.error("Mikrofon olishda xato:", err);
    }
  };

  const openAttachMenu = () => {
    if (attachMenuTimerRef.current) {
      window.clearTimeout(attachMenuTimerRef.current);
      attachMenuTimerRef.current = null;
    }
    setShowAttachMenu(true);
  };

  const scheduleAttachMenuClose = () => {
    if (!hoverMenuEnabled) return;
    if (attachMenuTimerRef.current) {
      window.clearTimeout(attachMenuTimerRef.current);
    }
    attachMenuTimerRef.current = window.setTimeout(() => {
      setShowAttachMenu(false);
    }, 120);
  };

  const handleAttachButtonClick = () => {
    if (hoverMenuEnabled) {
      openAttachMenu();
      return;
    }
    setShowAttachMenu((prev) => !prev);
  };

  const hasSendContent = text.trim() || pendingFile;

  return (
    <div className="sticky bottom-0 z-20 bg-white dark:bg-[#1a1a2e] border-t border-gray-200 dark:border-gray-700 shrink-0 safe-bottom">
      {/* Reply bar */}
      {replyTo && (
        <div className="flex items-center gap-2 px-3 py-2 bg-gray-50 dark:bg-[#2b2b2b] border-b border-gray-200 dark:border-gray-700">
          <div className="w-1 h-8 bg-[#419fd9] rounded-full shrink-0" />
          <div className="flex-1 min-w-0">
            <p className="text-xs font-semibold text-[#419fd9]">
              {replyTo.username}
            </p>
            <p className="text-xs text-gray-500 dark:text-gray-400 truncate">
              {replyTo.content || t("chat_photo_audio")}
            </p>
          </div>
          <button
            onClick={onCancelReply}
            className="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 shrink-0"
          >
            <i className="fas fa-times" />
          </button>
        </div>
      )}

      {/* File preview */}
      {pendingFile && (
        <div className="flex items-center gap-3 px-3 py-2 bg-gray-50 dark:bg-[#2b2b2b] border-b border-gray-200 dark:border-gray-700">
          <div className="relative w-16 h-16 rounded-lg overflow-hidden bg-gray-200 dark:bg-gray-700 shrink-0">
            {pendingFile.kind === "video" ? (
              <video
                src={pendingFile.previewUrl}
                className="w-full h-full object-cover"
                muted
              />
            ) : pendingFile.kind === "image" ? (
              <img
                src={pendingFile.previewUrl}
                alt="Preview"
                className="w-full h-full object-cover"
              />
            ) : (
              <div className="flex h-full w-full items-center justify-center text-gray-500 dark:text-gray-300">
                <i className="far fa-file-lines text-2xl" />
              </div>
            )}
            {uploading && (
              <div className="absolute inset-0 bg-black/40 flex items-center justify-center">
                <i className="fas fa-spinner fa-spin text-white" />
              </div>
            )}
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-sm text-gray-700 dark:text-gray-200 truncate">
              {pendingFile.file.name}
            </p>
            <p className="text-xs text-gray-400">
              {(pendingFile.file.size / 1024).toFixed(0)} KB
            </p>
          </div>
          <button
            onClick={cancelPendingFile}
            className="w-8 h-8 flex items-center justify-center text-gray-400 hover:text-red-500 rounded-full hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors shrink-0"
          >
            <i className="fas fa-times" />
          </button>
        </div>
      )}

      <div className="flex items-end gap-1 px-2 py-2">
        {/* Text input */}
        <div className="flex-1 relative">
          <div
            className="absolute inset-y-0 left-2 z-10 flex items-center"
            ref={attachMenuRef}
            onMouseEnter={hoverMenuEnabled ? openAttachMenu : undefined}
            onMouseLeave={hoverMenuEnabled ? scheduleAttachMenuClose : undefined}
          >
            <button
              onClick={handleAttachButtonClick}
              className="flex h-9 w-9 items-center justify-center rounded-full text-[#8d8d8d] transition-colors hover:bg-gray-100 hover:text-[#419fd9] dark:hover:bg-gray-800"
              type="button"
            >
              <i className="fas fa-paperclip text-lg rotate-45" />
            </button>

            {showAttachMenu && (
              <div className="absolute bottom-12 left-0 z-50 w-60 overflow-hidden rounded-xl border border-gray-200 bg-white shadow-xl dark:border-gray-700 dark:bg-[#1f2937]">
                <button
                  type="button"
                  onClick={() => photoInputRef.current?.click()}
                  className="group flex w-full items-center gap-3 px-4 py-2.5 text-left text-[15px] text-gray-900 transition-colors hover:bg-gray-100 focus-visible:bg-gray-100 focus-visible:outline-none dark:text-gray-100 dark:hover:bg-gray-800 dark:focus-visible:bg-gray-800"
                >
                  <i className="far fa-image w-5 text-center text-gray-500 transition-colors group-hover:text-[#419fd9] dark:text-gray-400" />
                  <span>{t("chat_photo")}</span>
                </button>
                <button
                  type="button"
                  onClick={() => videoInputRef.current?.click()}
                  className="group flex w-full items-center gap-3 px-4 py-2.5 text-left text-[15px] text-gray-900 transition-colors hover:bg-gray-100 focus-visible:bg-gray-100 focus-visible:outline-none dark:text-gray-100 dark:hover:bg-gray-800 dark:focus-visible:bg-gray-800"
                >
                  <i className="fas fa-video w-5 text-center text-gray-500 transition-colors group-hover:text-[#419fd9] dark:text-gray-400" />
                  <span>{tr("chat_video", "Video")}</span>
                </button>
                <button
                  type="button"
                  onClick={() => audioInputRef.current?.click()}
                  className="group flex w-full items-center gap-3 px-4 py-2.5 text-left text-[15px] text-gray-900 transition-colors hover:bg-gray-100 focus-visible:bg-gray-100 focus-visible:outline-none dark:text-gray-100 dark:hover:bg-gray-800 dark:focus-visible:bg-gray-800"
                >
                  <i className="fas fa-music w-5 text-center text-gray-500 transition-colors group-hover:text-[#419fd9] dark:text-gray-400" />
                  <span>{t("chat_voice_message")}</span>
                </button>
                <button
                  type="button"
                  onClick={() => documentInputRef.current?.click()}
                  className="group flex w-full items-center gap-3 px-4 py-2.5 text-left text-[15px] text-gray-900 transition-colors hover:bg-gray-100 focus-visible:bg-gray-100 focus-visible:outline-none dark:text-gray-100 dark:hover:bg-gray-800 dark:focus-visible:bg-gray-800"
                >
                  <i className="far fa-file-lines w-5 text-center text-gray-500 transition-colors group-hover:text-[#419fd9] dark:text-gray-400" />
                  <span>{tr("chat_document", "Document")}</span>
                </button>
                <button
                  type="button"
                  onClick={handleSendLocation}
                  className="group flex w-full items-center gap-3 px-4 py-2.5 text-left text-[15px] text-gray-900 transition-colors hover:bg-gray-100 focus-visible:bg-gray-100 focus-visible:outline-none dark:text-gray-100 dark:hover:bg-gray-800 dark:focus-visible:bg-gray-800"
                >
                  <i className={`fas ${locating ? "fa-spinner fa-spin" : "fa-map-marker-alt"} w-5 text-center text-gray-500 transition-colors group-hover:text-[#419fd9] dark:text-gray-400`} />
                  <span>{t("chat_location") || "Location"}</span>
                </button>
              </div>
            )}

            <input
              ref={photoInputRef}
              type="file"
              accept="image/*"
              className="hidden"
              onChange={handleImageSelect}
            />
            <input
              ref={videoInputRef}
              type="file"
              accept="video/*,.mp4,.mov,.avi,.webm,.mkv,.3gp"
              className="hidden"
              onChange={handleVideoSelect}
            />
            <input
              ref={audioInputRef}
              type="file"
              accept={AUDIO_ACCEPT}
              className="hidden"
              onChange={handleAudioFileSelect}
            />
            <input
              ref={documentInputRef}
              type="file"
              accept={DOCUMENT_ACCEPT}
              className="hidden"
              onChange={handleDocumentSelect}
            />
          </div>

          <textarea
            ref={textareaRef}
            value={text}
            onChange={(e) => setText(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder={
              pendingFile
                ? t("chat_add_caption") || "Izoh qo'shing..."
                : t("chat_write_message")
            }
            rows={1}
            disabled={disabled}
            className="w-full rounded-2xl border border-gray-200 bg-gray-50 py-2.5 pl-12 pr-4 text-[14px] outline-none resize-none max-h-32 transition-colors focus:border-[#419fd9] dark:border-gray-700 dark:bg-[#2b2b2b] dark:text-white"
            style={{ minHeight: 42 }}
          />
        </div>

        {/* Emoji */}
        <div className="relative shrink-0" ref={emojiRef}>
          <button
            onClick={() => setShowEmoji(!showEmoji)}
            className={`w-10 h-10 flex items-center justify-center rounded-full hover:bg-gray-100 dark:hover:bg-gray-800 transition-colors ${
              showEmoji
                ? "text-[#419fd9]"
                : "text-[#8d8d8d] hover:text-[#419fd9]"
            }`}
          >
            <i className="far fa-smile text-xl" />
          </button>
          {showEmoji && (
            <div className="absolute bottom-12 right-0 z-50">
              <EmojiPicker
                onEmojiClick={onEmojiClick}
                width={320}
                height={400}
                searchPlaceholder={t("chat_emoji_search")}
                previewConfig={{ showPreview: false }}
              />
            </div>
          )}
        </div>

        {/* Mic / Send */}
        {hasSendContent ? (
          <button
            onClick={handleSend}
            disabled={uploading}
            className="w-10 h-10 flex items-center justify-center text-[#419fd9] rounded-full hover:bg-[#419fd9]/10 transition-colors shrink-0 disabled:opacity-50"
          >
            <i
              className={`fas ${uploading ? "fa-spinner fa-spin" : "fa-paper-plane"} text-xl`}
            />
          </button>
        ) : (
          <button
            onClick={toggleRecording}
            className={`w-10 h-10 flex items-center justify-center rounded-full transition-colors shrink-0 ${
              recording
                ? "text-red-500 bg-red-50 dark:bg-red-900/30 animate-pulse"
                : "text-[#8d8d8d] hover:text-[#419fd9] hover:bg-gray-100 dark:hover:bg-gray-800"
            }`}
          >
            <i
              className={`fas ${recording ? "fa-stop" : "fa-microphone"} text-xl`}
            />
          </button>
        )}
      </div>
    </div>
  );
}
