import { useState, useEffect } from "react";
import { fetchJSON } from "@/utils/api";
import { useLanguage } from "@/context/LanguageContext";
import Avatar from "@/components/common/Avatar";
import Modal from "./Modal";

export default function AddMemberModal({ isOpen, onClose, type, targetId, onAdded }) {
  const { t } = useLanguage();
  const [search, setSearch] = useState("");
  const [users, setUsers] = useState([]);
  const [selected, setSelected] = useState(new Set());
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (isOpen && targetId) loadUsers("");
  }, [isOpen, targetId]);

  const loadUsers = async (q) => {
    try {
      const param = type === "group" ? `excludeGroupId=${targetId}` : `excludeChannelId=${targetId}`;
      const data = await fetchJSON(`/api/users/search?${param}${q ? `&q=${q}` : ""}`);
      setUsers(data);
    } catch (err) {
      console.error("Userlarni yuklashda xato:", err);
    }
  };

  const handleSearch = (q) => {
    setSearch(q);
    loadUsers(q);
  };

  const toggleUser = (userId) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(userId)) next.delete(userId);
      else next.add(userId);
      return next;
    });
  };

  const handleAdd = async () => {
    if (selected.size === 0) return;
    setLoading(true);
    try {
      const url = type === "group"
        ? `/api/groups/${targetId}/members`
        : `/api/channels/${targetId}/subscribers`;

      await fetchJSON(url, {
        method: "POST",
        body: JSON.stringify({ userIds: [...selected] }),
      });

      onAdded?.();
      setSelected(new Set());
      setSearch("");
      onClose();
    } catch (err) {
      console.error("Qo'shishda xato:", err);
    } finally {
      setLoading(false);
    }
  };

  const title = type === "group" ? t("modal_add_member") : t("modal_add_subscriber");

  return (
    <Modal isOpen={isOpen} onClose={onClose} title={title}>
      <div className="p-4">
        {/* Selected chips */}
        {selected.size > 0 && (
          <div className="flex flex-wrap gap-2 mb-3">
            {users.filter((u) => selected.has(u.id)).map((u) => (
              <span
                key={u.id}
                className="inline-flex items-center gap-1 px-3 py-1 bg-blue-100 dark:bg-blue-900/30 text-blue-600 rounded-full text-sm"
              >
                {u.username}
                <button onClick={() => toggleUser(u.id)} className="hover:text-red-500">
                  <i className="fas fa-times text-xs" />
                </button>
              </span>
            ))}
          </div>
        )}

        {/* Search */}
        <div className="relative mb-3">
          <i className="fas fa-search absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 text-sm" />
          <input
            type="text"
            value={search}
            onChange={(e) => handleSearch(e.target.value)}
            placeholder={t("contacts_search")}
            className="w-full pl-9 pr-4 py-2.5 bg-gray-100 dark:bg-gray-800 rounded-xl text-sm outline-none dark:text-white"
          />
        </div>

        {/* User list */}
        <div className="max-h-60 overflow-y-auto space-y-1">
          {users.map((u) => (
            <label
              key={u.id}
              className="flex items-center gap-3 p-2.5 rounded-lg cursor-pointer hover:bg-gray-50 dark:hover:bg-gray-800"
            >
              <input
                type="checkbox"
                checked={selected.has(u.id)}
                onChange={() => toggleUser(u.id)}
                className="w-4 h-4 text-blue-600 rounded"
              />
              <Avatar src={u.avatar} name={u.username} size={32} />
              <span className="text-sm text-gray-900 dark:text-white">{u.username}</span>
            </label>
          ))}
        </div>

        {/* Add button */}
        <button
          onClick={handleAdd}
          disabled={selected.size === 0 || loading}
          className="w-full mt-4 py-3 bg-blue-500 text-white rounded-xl font-semibold hover:bg-blue-600 disabled:opacity-50 transition-colors"
        >
          {loading ? <i className="fas fa-spinner fa-spin" /> : `${t("add")} (${selected.size})`}
        </button>
      </div>
    </Modal>
  );
}
