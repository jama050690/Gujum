import { useState } from "react";
import { useAuth } from "@/context/AuthContext";
import { useLanguage } from "@/context/LanguageContext";
import { fetchJSON } from "@/utils/api";
import Modal from "./Modal";

export default function NewGroupModal({ isOpen, onClose, onCreated }) {
  const { user } = useAuth();
  const { t } = useLanguage();
  const [name, setName] = useState("");
  const [avatar, setAvatar] = useState("");
  const [allowDownload, setAllowDownload] = useState(false);
  const [loading, setLoading] = useState(false);

  const handleAvatarChange = (e) => {
    const file = e.target.files[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = (ev) => setAvatar(ev.target.result);
    reader.readAsDataURL(file);
  };

  const handleCreate = async () => {
    if (!name.trim()) return;
    setLoading(true);
    try {
      const data = await fetchJSON("/api/groups", {
        method: "POST",
        body: JSON.stringify({ name: name.trim(), username: user, avatar: avatar || null, allow_download: allowDownload }),
      });
      onCreated?.(data.group);
      setName("");
      setAvatar("");
      setAllowDownload(false);
      onClose();
    } catch (err) {
      console.error("Guruh yaratishda xato:", err);
    } finally {
      setLoading(false);
    }
  };

  return (
    <Modal isOpen={isOpen} onClose={onClose} title={t("group_new")}>
      <div className="p-5 space-y-4">
        {/* Avatar */}
        <div className="flex justify-center">
          <label className="relative cursor-pointer group">
            <div className="w-20 h-20 rounded-full bg-green-500 flex items-center justify-center overflow-hidden">
              {avatar ? (
                <img src={avatar} alt="avatar" className="w-full h-full object-cover" />
              ) : (
                <i className="fas fa-camera text-white text-2xl" />
              )}
            </div>
            <input type="file" accept="image/*" className="hidden" onChange={handleAvatarChange} />
          </label>
        </div>

        {/* Name */}
        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">{t("group_name")}</label>
          <input
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder={t("group_name_placeholder")}
            className="w-full px-4 py-3 border border-gray-300 dark:border-gray-600 rounded-xl outline-none focus:ring-2 focus:ring-green-500 dark:bg-gray-800 dark:text-white"
          />
        </div>

        {/* Allow download toggle */}
        <label className="flex items-center justify-between cursor-pointer">
          <div className="flex items-center gap-2">
            <i className="fas fa-download text-gray-400 text-sm" />
            <span className="text-sm text-gray-700 dark:text-gray-300">{t("allow_download") || "Yuklab olishga ruxsat"}</span>
          </div>
          <div
            onClick={() => setAllowDownload(!allowDownload)}
            className={`relative w-11 h-6 rounded-full transition-colors ${allowDownload ? "bg-green-500" : "bg-gray-300 dark:bg-gray-600"}`}
          >
            <div className={`absolute top-0.5 left-0.5 w-5 h-5 bg-white rounded-full shadow transition-transform ${allowDownload ? "translate-x-5" : ""}`} />
          </div>
        </label>

        <button
          onClick={handleCreate}
          disabled={!name.trim() || loading}
          className="w-full py-3 bg-green-500 text-white rounded-xl font-semibold hover:bg-green-600 disabled:opacity-50 transition-colors"
        >
          {loading ? <i className="fas fa-spinner fa-spin" /> : t("create")}
        </button>
      </div>
    </Modal>
  );
}
