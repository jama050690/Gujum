import { useEffect, useMemo, useState } from "react";
import { useAuth } from "@/context/AuthContext";
import { useLanguage } from "@/context/LanguageContext";
import { fetchJSON } from "@/utils/api";
import Avatar from "@/components/common/Avatar";
import Modal from "./Modal";

const DRAWER_COPY = {
  uz: {
    title: "Hamjamiyatlar",
    groups: "Guruhlar",
    channels: "Kanallar",
    emptyGroups: "Guruhlar topilmadi",
    emptyChannels: "Kanallar topilmadi",
  },
  ru: {
    title: "Communities",
    groups: "Groups",
    channels: "Channels",
    emptyGroups: "No groups yet",
    emptyChannels: "No channels yet",
  },
  en: {
    title: "Communities",
    groups: "Groups",
    channels: "Channels",
    emptyGroups: "No groups yet",
    emptyChannels: "No channels yet",
  },
};

function getCopy(lang) {
  return DRAWER_COPY[lang] || DRAWER_COPY.en;
}

export default function CommunitiesModal({
  isOpen,
  onClose,
  onSelectChat,
  onCreateGroup,
  onCreateChannel,
}) {
  const { user } = useAuth();
  const { t, lang } = useLanguage();
  const copy = getCopy(lang);
  const [activeTab, setActiveTab] = useState("group");
  const [groups, setGroups] = useState([]);
  const [channels, setChannels] = useState([]);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (!isOpen || !user) return;

    setActiveTab("group");

    let cancelled = false;

    async function load() {
      setLoading(true);
      try {
        const [groupData, channelData] = await Promise.all([
          fetchJSON(`/api/groups?username=${user}`),
          fetchJSON(`/api/channels?username=${user}`),
        ]);
        if (!cancelled) {
          setGroups(Array.isArray(groupData) ? groupData : []);
          setChannels(Array.isArray(channelData) ? channelData : []);
        }
      } catch (error) {
        if (!cancelled) {
          setGroups([]);
          setChannels([]);
        }
        console.error("Communities yuklanmadi:", error);
      } finally {
        if (!cancelled) {
          setLoading(false);
        }
      }
    }

    load();

    return () => {
      cancelled = true;
    };
  }, [isOpen, user]);

  const items = useMemo(
    () => (activeTab === "group" ? groups : channels),
    [activeTab, groups, channels]
  );

  const emptyLabel = activeTab === "group" ? copy.emptyGroups : copy.emptyChannels;
  const counterLabel = activeTab === "group" ? t("chat_members") : t("chat_subscribers");

  const handleCreate = () => {
    onClose();
    if (activeTab === "group") {
      onCreateGroup?.();
      return;
    }
    onCreateChannel?.();
  };

  return (
    <Modal isOpen={isOpen} onClose={onClose} title={copy.title}>
      <div className="p-4">
        <div className="grid grid-cols-2 gap-2 rounded-2xl bg-[#edf1f7] p-1 dark:bg-[#253341]">
          <TabButton
            active={activeTab === "group"}
            label={copy.groups}
            onClick={() => setActiveTab("group")}
          />
          <TabButton
            active={activeTab === "channel"}
            label={copy.channels}
            onClick={() => setActiveTab("channel")}
          />
        </div>

        <div className="mt-4 max-h-[360px] space-y-1 overflow-y-auto">
          {loading ? (
            <p className="py-10 text-center text-sm text-gray-400">{t("loading")}</p>
          ) : items.length === 0 ? (
            <p className="py-10 text-center text-sm text-gray-400">{emptyLabel}</p>
          ) : (
            items.map((item) => (
              <button
                key={`${activeTab}-${item.id ?? item.name}`}
                onClick={() => {
                  onSelectChat?.({
                    ...item,
                    type: activeTab,
                  });
                  onClose();
                }}
                className="flex w-full items-center gap-3 rounded-2xl px-3 py-2.5 text-left transition-colors hover:bg-gray-50 dark:hover:bg-gray-800"
              >
                <Avatar src={item.avatar} name={item.name} size={46} />
                <div className="min-w-0 flex-1">
                  <div className="truncate text-sm font-semibold text-gray-900 dark:text-white">
                    {item.name}
                  </div>
                  <div className="text-xs text-gray-400 dark:text-gray-500">
                    {item.peopleCount ?? 0} {counterLabel}
                  </div>
                </div>
              </button>
            ))
          )}
        </div>

        <button
          onClick={handleCreate}
          className="mt-4 flex w-full items-center justify-center rounded-[28px] bg-[#4c6fa7] px-4 py-3 text-sm font-semibold text-white transition-colors hover:bg-[#436595]"
        >
          {activeTab === "group" ? t("group_new") : t("channel_new")}
        </button>
      </div>
    </Modal>
  );
}

function TabButton({ active, label, onClick }) {
  return (
    <button
      onClick={onClick}
      className={`rounded-[18px] px-4 py-2 text-sm font-semibold transition-colors ${
        active
          ? "bg-white text-[#233042] shadow-sm dark:bg-[#1c252e] dark:text-white"
          : "text-gray-500 dark:text-gray-300"
      }`}
    >
      {label}
    </button>
  );
}
