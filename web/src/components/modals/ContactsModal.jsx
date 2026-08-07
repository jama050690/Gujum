import { useEffect, useMemo, useState } from "react";
import { fetchJSON } from "@/utils/api";
import { useLanguage } from "@/context/LanguageContext";
import { getSyncedContacts, saveSyncedContacts } from "@/utils/storage";
import Avatar from "@/components/common/Avatar";
import Modal from "./Modal";

const hasContactPicker = "contacts" in navigator && "ContactsManager" in window;

export default function ContactsModal({ isOpen, onClose, onSelectUser }) {
  const { t } = useLanguage();
  const tr = (key, fallback) => {
    const value = t(key);
    return value === key ? fallback : value;
  };

  const [phoneContacts, setPhoneContacts] = useState([]);
  const [searchResults, setSearchResults] = useState([]);
  const [search, setSearch] = useState("");
  const [sortAZ, setSortAZ] = useState(false);
  const [syncing, setSyncing] = useState(false);
  const [searching, setSearching] = useState(false);

  const getContactLabel = (contact) =>
    contact.full_name || contact.fullName || contact.username || "";

  const getContactSearchText = (contact) =>
    [contact.username, contact.full_name, contact.fullName]
      .filter(Boolean)
      .join(" ")
      .toLowerCase();

  useEffect(() => {
    if (!isOpen) return;
    setSearch("");
    setSearchResults([]);
    setPhoneContacts(getSyncedContacts());
  }, [isOpen]);

  const handleSync = async () => {
    if (!hasContactPicker) return;
    setSyncing(true);
    try {
      const contacts = await navigator.contacts.select(["name", "tel"], { multiple: true });
      const phones = contacts.flatMap((c) => c.tel || []);
      if (phones.length === 0) return;

      const matched = await fetchJSON("/api/users/phone-contacts", {
        method: "POST",
        body: JSON.stringify({ phones }),
      });
      saveSyncedContacts(matched);
      setPhoneContacts(matched);
    } catch (err) {
      if (err?.name !== "TypeError") {
        console.error("Kontaktlarni sinxronlashda xato:", err);
      }
    } finally {
      setSyncing(false);
    }
  };

  const handleUserSearch = async () => {
    const query = search.trim();
    if (!query) {
      setSearchResults([]);
      return;
    }

    setSearching(true);
    try {
      const data = await fetchJSON(`/api/users/search?q=${encodeURIComponent(query)}`);
      setSearchResults(data.filter((item) => item.username));
    } catch (err) {
      console.error("User qidiruvida xato:", err);
      setSearchResults([]);
    } finally {
      setSearching(false);
    }
  };

  const filteredPhoneContacts = useMemo(() => {
    let items = [...phoneContacts];
    if (search.trim()) {
      const query = search.trim().toLowerCase();
      items = items.filter((item) => getContactSearchText(item).includes(query));
    }
    if (sortAZ) {
      items.sort((a, b) => getContactLabel(a).localeCompare(getContactLabel(b)));
    }
    return items;
  }, [phoneContacts, search, sortAZ]);

  const renderContactList = (items) =>
    items.map((item) => (
      <button
        key={item.id || item.username}
        type="button"
        onClick={() => {
          onSelectUser?.(item);
          onClose();
        }}
        className="w-full flex items-center gap-3 p-2.5 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-800 text-left"
      >
        <Avatar src={item.avatar} name={getContactLabel(item)} size={40} />
        <div className="min-w-0">
          <span className="block text-sm font-medium text-gray-900 dark:text-white truncate">
            {getContactLabel(item)}
          </span>
          {item.username && (
            <span className="block text-xs text-gray-400 truncate">@{item.username}</span>
          )}
        </div>
      </button>
    ));

  return (
    <Modal isOpen={isOpen} onClose={onClose} title={t("contacts_title")}>
      <div className="p-4">
        <div className="flex gap-2 mb-3">
          <div className="flex-1 relative">
            <i className="fas fa-search absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 text-sm" />
            <input
              type="text"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  handleUserSearch();
                }
              }}
              placeholder={tr("search_hint", "Username yoki ism")}
              className="w-full pl-9 pr-4 py-2.5 bg-gray-100 dark:bg-gray-800 rounded-xl text-sm outline-none dark:text-white"
            />
          </div>

          <button
            type="button"
            onClick={() => setSortAZ((prev) => !prev)}
            className={`px-3 rounded-xl text-sm font-medium transition-colors ${
              sortAZ
                ? "bg-blue-500 text-white"
                : "bg-gray-100 dark:bg-gray-800 text-gray-600 dark:text-gray-300"
            }`}
          >
            A-Z
          </button>

          <button
            type="button"
            onClick={handleUserSearch}
            disabled={searching}
            className="px-4 py-2 bg-blue-500 text-white rounded-xl text-sm font-medium hover:bg-blue-600 transition-colors disabled:opacity-50"
          >
            {searching ? "..." : tr("chat_search_button", "Qidirish")}
          </button>
        </div>

        {hasContactPicker && (
          <div className="mb-3">
            <button
              type="button"
              onClick={handleSync}
              disabled={syncing}
              className="w-full flex items-center justify-center gap-2 py-2.5 bg-blue-50 dark:bg-blue-900/30 text-blue-600 dark:text-blue-400 rounded-xl text-sm font-medium hover:bg-blue-100 dark:hover:bg-blue-900/50 transition-colors disabled:opacity-50"
            >
              <i className={`fas ${syncing ? "fa-spinner fa-spin" : "fa-address-book"}`} />
              {t("contacts_sync_button")}
            </button>
          </div>
        )}

        <div className="max-h-80 overflow-y-auto space-y-1">
          {search.trim().length > 0 ? (
            searching ? (
              <p className="text-center text-sm text-gray-400 py-8">{tr("loading", "Yuklanmoqda...")}</p>
            ) : searchResults.length > 0 ? (
              <>
                <p className="text-xs font-semibold text-gray-400 dark:text-gray-500 uppercase px-1 pt-1 pb-2">
                  {t("search_global_results")}
                </p>
                {renderContactList(searchResults)}
              </>
            ) : (
              <div className="text-center py-8">
                <i className="fas fa-search text-3xl text-gray-300 dark:text-gray-600 mb-3" />
                <p className="text-sm text-gray-400">{t("contacts_not_found")}</p>
              </div>
            )
          ) : filteredPhoneContacts.length > 0 ? (
            <>
              <p className="text-xs font-semibold text-gray-400 dark:text-gray-500 uppercase px-1 pt-1 pb-2">
                {t("contacts_phone_section")}
              </p>
              {renderContactList(filteredPhoneContacts)}
            </>
          ) : (
            <div className="text-center py-8">
              <i className="fas fa-address-book text-3xl text-gray-300 dark:text-gray-600 mb-3" />
              <p className="text-sm text-gray-400">{t("contacts_empty")}</p>
              <p className="text-xs text-gray-400 mt-1">
                {tr("search_tap_to_chat", "Chat boshlash uchun qidiring")}
              </p>
            </div>
          )}
        </div>
      </div>
    </Modal>
  );
}
