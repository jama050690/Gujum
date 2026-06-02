import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { fetchJSON } from "@/utils/api";
import { useAuth } from "@/context/AuthContext";
import { useLanguage } from "@/context/LanguageContext";

const STAT_CARDS = [
  { key: "users", label: "Users", icon: "fa-users" },
  { key: "admins", label: "Admins", icon: "fa-user-shield" },
  { key: "chats", label: "Chats", icon: "fa-comments" },
  { key: "messages", label: "Messages", icon: "fa-paper-plane" },
  { key: "groups", label: "Groups", icon: "fa-user-group" },
  { key: "channels", label: "Channels", icon: "fa-bullhorn" },
  { key: "activeToday", label: "Active Today", icon: "fa-bolt" },
];

export default function AdminDashboardPage() {
  const navigate = useNavigate();
  const { role, user, logout } = useAuth();
  const { lang } = useLanguage();
  const [data, setData] = useState(null);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);
  const [actionMessage, setActionMessage] = useState("");
  const [deletingUsername, setDeletingUsername] = useState("");

  const loadDashboard = () => {
    setLoading(true);
    setError("");
    fetchJSON("/api/admin/dashboard")
      .then((response) => {
        setData(response);
      })
      .catch((err) => {
        setError(err.message || "Dashboard yuklanmadi");
      })
      .finally(() => {
        setLoading(false);
      });
  };

  useEffect(() => {
    if (role !== "admin") return;

    loadDashboard();
  }, [role]);

  const handleLogout = async () => {
    await logout();
    navigate(`/${lang}/login`);
  };

  const handleDeleteUser = async (username) => {
    const confirmed = window.confirm(`"${username}" foydalanuvchisini o'chirmoqchimisiz? Bu amal qaytmaydi.`);
    if (!confirmed) return;

    setDeletingUsername(username);
    setActionMessage("");
    setError("");

    try {
      const response = await fetchJSON(`/api/admin/users/${encodeURIComponent(username)}`, {
        method: "DELETE",
      });

      setData((prev) => {
        if (!prev) return prev;
        const nextUsers = (prev.usersList || []).filter((entry) => entry.username !== username);
        const nextRecent = (prev.recentUsers || []).filter((entry) => entry.username !== username);

        return {
          ...prev,
          stats: {
            ...prev.stats,
            users: Math.max((prev.stats?.users || 1) - 1, 0),
          },
          usersList: nextUsers,
          recentUsers: nextRecent,
        };
      });

      setActionMessage(`${response.username} o'chirildi`);
    } catch (err) {
      setError(err.message || "Userni o'chirib bo'lmadi");
    } finally {
      setDeletingUsername("");
    }
  };

  if (role !== "admin") return null;

  return (
    <div className="min-h-[100dvh] bg-[radial-gradient(circle_at_top,_#f8f3e7_0%,_#f4ede1_35%,_#ece4d7_100%)] px-4 py-6 text-[#231f19] md:px-8">
      <div className="mx-auto max-w-7xl">
        <div className="overflow-hidden rounded-[32px] border border-black/10 bg-white/70 shadow-[0_24px_80px_rgba(58,40,18,0.12)] backdrop-blur">
          <div className="border-b border-black/8 bg-[linear-gradient(135deg,_#1c3b36,_#29574d_45%,_#d7b56d_100%)] px-6 py-8 text-white md:px-10">
            <div className="flex flex-col gap-5 md:flex-row md:items-end md:justify-between">
              <div>
                <p className="text-xs uppercase tracking-[0.35em] text-white/70">Gujum Control</p>
                <h1 className="mt-3 text-3xl font-black tracking-tight md:text-5xl">Admin Dashboard</h1>
                <p className="mt-3 max-w-2xl text-sm text-white/80 md:text-base">
                  Platformadagi foydalanuvchilar, chatlar va activity ko‘rsatkichlari shu yerda jamlangan.
                </p>
              </div>
              <div className="flex flex-wrap gap-3">
                <button
                  type="button"
                  onClick={() => navigate(`/${lang}`)}
                  className="rounded-full border border-white/30 bg-white/10 px-5 py-3 text-sm font-semibold text-white transition hover:bg-white/20"
                >
                  Chatga qaytish
                </button>
                <button
                  type="button"
                  onClick={handleLogout}
                  className="rounded-full bg-[#fff4dd] px-5 py-3 text-sm font-semibold text-[#523300] transition hover:bg-[#ffe9b8]"
                >
                  Chiqish
                </button>
              </div>
            </div>
          </div>

          <div className="px-6 py-6 md:px-10 md:py-8">
            {loading && <p className="text-sm text-black/60">Dashboard yuklanmoqda...</p>}
            {error && !loading && (
              <div className="rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
                {error}
              </div>
            )}
            {actionMessage && !loading && (
              <div className="mt-3 rounded-2xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-700">
                {actionMessage}
              </div>
            )}

            {!loading && data && (
              <>
                <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
                  {STAT_CARDS.map((card) => (
                    <div
                      key={card.key}
                      className="rounded-[24px] border border-black/8 bg-[linear-gradient(180deg,_rgba(255,255,255,0.95),_rgba(243,237,226,0.9))] p-5 shadow-[0_10px_30px_rgba(44,33,16,0.08)]"
                    >
                      <div className="flex items-center justify-between">
                        <span className="text-sm font-medium text-black/55">{card.label}</span>
                        <i className={`fas ${card.icon} text-[#9c6b21]`} />
                      </div>
                      <div className="mt-4 text-3xl font-black tracking-tight">
                        {data.stats?.[card.key] ?? 0}
                      </div>
                    </div>
                  ))}
                </div>

                <div className="mt-6 grid gap-6 xl:grid-cols-[1.2fr_0.8fr]">
                  <section className="rounded-[28px] border border-black/8 bg-white/85 p-6 shadow-[0_12px_40px_rgba(41,30,15,0.08)]">
                    <div className="flex items-center justify-between gap-3">
                      <div>
                        <h2 className="text-xl font-black">Oxirgi foydalanuvchilar</h2>
                        <p className="mt-1 text-sm text-black/55">Yaqinda tizimga qo‘shilgan yoki ko‘rinib turgan akkauntlar.</p>
                      </div>
                      <span className="rounded-full bg-[#1c3b36] px-3 py-1 text-xs font-semibold text-white">
                        {data.recentUsers?.length || 0} ta
                      </span>
                    </div>

                    <div className="mt-5 space-y-3">
                      {(data.recentUsers || []).map((entry) => (
                        <div
                          key={`${entry.username}-${entry.email}`}
                          className="flex items-center justify-between gap-4 rounded-2xl border border-black/6 bg-[#fcfaf6] px-4 py-3"
                        >
                          <div className="min-w-0">
                            <p className="truncate text-sm font-bold">{entry.full_name || entry.username}</p>
                            <p className="truncate text-xs text-black/50">@{entry.username} • {entry.email}</p>
                          </div>
                          <div className="text-right">
                            <span className={`rounded-full px-3 py-1 text-xs font-semibold ${entry.role === "admin" ? "bg-[#1c3b36] text-white" : "bg-[#eadfca] text-[#5c4322]"}`}>
                              {entry.role}
                            </span>
                            <p className="mt-2 text-xs text-black/45">
                              {entry.last_seen ? new Date(entry.last_seen).toLocaleString() : "last seen yo‘q"}
                            </p>
                          </div>
                        </div>
                      ))}
                    </div>
                  </section>

                  <section className="rounded-[28px] border border-black/8 bg-[#1f211e] p-6 text-white shadow-[0_12px_40px_rgba(18,18,18,0.18)]">
                    <p className="text-xs uppercase tracking-[0.3em] text-white/45">Session</p>
                    <h2 className="mt-3 text-2xl font-black">Admin nazorati faol</h2>
                    <p className="mt-3 text-sm text-white/70">
                      Siz hozir <span className="font-semibold text-white">{data.session?.username}</span> akkaunti bilan kirdingiz.
                    </p>
                    <div className="mt-6 rounded-3xl border border-white/10 bg-white/5 p-4">
                      <p className="text-xs text-white/50">Role</p>
                      <p className="mt-2 text-lg font-bold">{data.session?.role}</p>
                    </div>
                    <div className="mt-4 rounded-3xl border border-white/10 bg-white/5 p-4">
                      <p className="text-xs text-white/50">Quick note</p>
                      <p className="mt-2 text-sm leading-6 text-white/72">
                        Bu dashboard hozircha kuzatuv va nazorat uchun. Keyinroq user boshqaruvi, bloklash va content moderation action’larini ham qo‘shishimiz mumkin.
                      </p>
                    </div>
                  </section>
                </div>

                <section className="mt-6 rounded-[28px] border border-black/8 bg-white/90 p-6 shadow-[0_12px_40px_rgba(41,30,15,0.08)]">
                  <div className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
                    <div>
                      <h2 className="text-xl font-black">Barcha foydalanuvchilar</h2>
                      <p className="mt-1 text-sm text-black/55">
                        Dashboardda userlar chiqmayotganining sababi oldin faqat so'nggi 8 ta user ko'rsatilgan edi. Endi to'liq ro'yxat shu yerda.
                      </p>
                    </div>
                    <button
                      type="button"
                      onClick={loadDashboard}
                      className="rounded-full border border-black/10 bg-[#f4ede1] px-4 py-2 text-sm font-semibold text-[#3c2f1f] transition hover:bg-[#eadfca]"
                    >
                      Yangilash
                    </button>
                  </div>

                  <div className="mt-5 overflow-x-auto">
                    <table className="min-w-full text-left">
                      <thead>
                        <tr className="border-b border-black/8 text-xs uppercase tracking-[0.2em] text-black/45">
                          <th className="px-3 py-3">User</th>
                          <th className="px-3 py-3">Email</th>
                          <th className="px-3 py-3">Role</th>
                          <th className="px-3 py-3">Last seen</th>
                          <th className="px-3 py-3 text-right">Action</th>
                        </tr>
                      </thead>
                      <tbody>
                        {(data.usersList || []).map((entry) => {
                          const isCurrentUser = entry.username === user;
                          const isAdminUser = entry.role === "admin";
                          const isDeleting = deletingUsername === entry.username;

                          return (
                            <tr key={entry.id || entry.username} className="border-b border-black/6 last:border-b-0">
                              <td className="px-3 py-4">
                                <p className="font-semibold text-[#231f19]">{entry.full_name || entry.username}</p>
                                <p className="text-xs text-black/50">@{entry.username}</p>
                              </td>
                              <td className="px-3 py-4 text-sm text-black/65">{entry.email}</td>
                              <td className="px-3 py-4">
                                <span className={`rounded-full px-3 py-1 text-xs font-semibold ${isAdminUser ? "bg-[#1c3b36] text-white" : "bg-[#eadfca] text-[#5c4322]"}`}>
                                  {entry.role}
                                </span>
                              </td>
                              <td className="px-3 py-4 text-sm text-black/55">
                                {entry.last_seen ? new Date(entry.last_seen).toLocaleString() : "last seen yo'q"}
                              </td>
                              <td className="px-3 py-4 text-right">
                                <button
                                  type="button"
                                  disabled={isCurrentUser || isAdminUser || isDeleting}
                                  onClick={() => handleDeleteUser(entry.username)}
                                  className={`rounded-full px-4 py-2 text-sm font-semibold transition ${
                                    isCurrentUser || isAdminUser
                                      ? "cursor-not-allowed bg-gray-100 text-gray-400"
                                      : "bg-red-50 text-red-600 hover:bg-red-100"
                                  }`}
                                >
                                  {isDeleting ? "O'chirilmoqda..." : isCurrentUser ? "Siz" : isAdminUser ? "Admin" : "Delete"}
                                </button>
                              </td>
                            </tr>
                          );
                        })}
                      </tbody>
                    </table>
                  </div>
                </section>
              </>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
