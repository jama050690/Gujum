import { useState, useEffect } from "react";
import { useAuth } from "@/context/AuthContext";
import { useLanguage } from "@/context/LanguageContext";
import { fetchJSON } from "@/utils/api";
import Avatar from "@/components/common/Avatar";
import SharedMedia from "./SharedMedia";

export default function GroupInfo({ group, onAddMember, onDelete }) {
  const { user } = useAuth();
  const { t } = useLanguage();
  const [members, setMembers] = useState([]);
  const [deleting, setDeleting] = useState(false);
  const [onlineCount, setOnlineCount] = useState(0);

  useEffect(() => {
    loadMembers();
  }, [group.id]);

  const loadMembers = async () => {
    try {
      const data = await fetchJSON(`/api/groups/${group.id}/members`);
      setMembers(data);
      setOnlineCount(data.filter((m) => m.online).length);
    } catch (err) {
      console.error("A'zolarni yuklashda xato:", err);
    }
  };

  const handleDelete = async () => {
    if (!confirm("Guruhni o'chirishni xohlaysizmi?")) return;
    setDeleting(true);
    try {
      await fetchJSON(`/api/groups/${group.id}`, {
        method: "DELETE",
        body: JSON.stringify({ username: user }),
      });
      onDelete?.();
    } catch (err) {
      alert(err.message || "Guruhni o'chirishda xato");
    } finally {
      setDeleting(false);
    }
  };

  return (
    <div>
      {/* Group avatar + name */}
      <div className="flex flex-col items-center text-center pt-6 pb-4 px-4">
        <div className="w-20 h-20 rounded-full bg-green-500 flex items-center justify-center">
          {group.avatar ? (
            <img src={group.avatar} alt={group.name} className="w-20 h-20 rounded-full object-cover" />
          ) : (
            <i className="fas fa-users text-white text-3xl" />
          )}
        </div>
        <h3 className="text-xl font-bold text-gray-900 dark:text-white mt-3">{group.name}</h3>
        <p className="text-sm text-gray-400">
          {members.length} {t("chat_members")}{onlineCount > 0 ? `, ${onlineCount} ${t("online").toLowerCase()}` : ""}
        </p>
      </div>

      {/* Quick actions */}
      <div className="flex justify-center gap-6 pb-4 px-4">
        <QuickAction icon="fa-bell" label={t("chat_mute_short")} />
        <QuickAction icon="fa-flag" label={t("chat_report")} />
        <QuickAction icon="fa-sign-out-alt" label={t("group_leave")} onClick={handleDelete} />
      </div>

      {/* Description */}
      {group.description && (
        <div className="border-t border-gray-200 dark:border-gray-700 py-3 px-4">
          <p className="text-sm text-gray-900 dark:text-white whitespace-pre-wrap">{group.description}</p>
          <p className="text-xs text-gray-400 mt-1">{t("channel_desc")}</p>
        </div>
      )}

      {/* Shared Media */}
      <div className="px-2">
        <SharedMedia />
      </div>

      {/* Members */}
      <div className="border-t border-gray-200 dark:border-gray-700 pt-3 px-4">
        <div className="flex items-center justify-between mb-3">
          <div className="flex items-center gap-2">
            <i className="fas fa-users text-gray-400 text-sm" />
            <h4 className="text-sm font-semibold text-gray-900 dark:text-white uppercase">{members.length} {t("chat_members").toUpperCase()}</h4>
          </div>
          <button
            onClick={() => onAddMember?.("group", group.id)}
            className="text-blue-500 text-sm hover:underline"
          >
            <i className="fas fa-plus mr-1" />{t("add")}
          </button>
        </div>

        <div className="space-y-1">
          {members.map((m) => (
            <div key={m.id} className="flex items-center gap-3 p-2 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-800">
              <Avatar src={m.avatar} name={m.username} size={36} />
              <div className="flex-1 min-w-0">
                <p className="text-sm font-medium text-gray-900 dark:text-white truncate">{m.username}</p>
                {m.role === "admin" && (
                  <p className="text-xs text-blue-500">Admin</p>
                )}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

function QuickAction({ icon, label, onClick }) {
  return (
    <button
      onClick={onClick}
      className="flex flex-col items-center gap-1.5 min-w-18 py-2 px-3 rounded-xl border border-gray-200 dark:border-gray-700 hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors"
    >
      <i className={`fas ${icon} text-[#419fd9]`} />
      <span className="text-xs text-gray-600 dark:text-gray-400">{label}</span>
    </button>
  );
}
