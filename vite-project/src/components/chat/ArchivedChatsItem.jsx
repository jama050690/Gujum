import { useLanguage } from "@/context/LanguageContext";

export default function ArchivedChatsItem({ storiesCount = 1, onClick }) {
  const { t } = useLanguage();
  return (
    <button
      type="button"
      onClick={onClick}
      className="w-full flex items-center gap-3 px-3 py-3 bg-white dark:bg-[#212121] hover:bg-gray-100 dark:hover:bg-[#2b2b2b] transition-colors border-b border-gray-100 dark:border-gray-800 text-left"
    >
      <div className="relative w-[58px] h-[58px] shrink-0">
        <div className="absolute inset-0 rounded-full border-2 border-[#2eb6a4]" />
        <div className="absolute inset-[4px] rounded-full border-[3px] border-[#2f9ed8]" />
        <div className="absolute inset-[9px] rounded-full bg-[#bfbfbf] flex items-center justify-center">
          <i className="fas fa-box-archive text-white text-lg" />
        </div>
      </div>

      <div className="min-w-0">
        <p className="text-base font-semibold text-gray-900 dark:text-white">{t("archive_title")}</p>
        <p className="text-sm text-[#7c8d9b] dark:text-gray-400">
          {storiesCount} new {storiesCount === 1 ? "story" : "stories"}
        </p>
      </div>
      <i className="fas fa-chevron-right ml-auto text-gray-400 text-xs" />
    </button>
  );
}
