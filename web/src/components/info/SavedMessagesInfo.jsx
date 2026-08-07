import { useChat } from "@/context/ChatContext";
import { useLanguage } from "@/context/LanguageContext";
import SharedMedia from "./SharedMedia";

export default function SavedMessagesInfo() {
  const { messages } = useChat();
  const { t } = useLanguage();

  return (
    <div className="p-4">
      {/* Avatar + Name */}
      <div className="flex flex-col items-center text-center mb-6">
        <div className="w-20 h-20 rounded-full bg-[#6c9fd2] flex items-center justify-center">
          <i className="fas fa-bookmark text-white text-3xl" />
        </div>
        <h3 className="text-xl font-bold text-gray-900 dark:text-white mt-3">{t("chat_saved_messages")}</h3>
        <p className="text-sm text-gray-400">{messages.length} ta xabar</p>
      </div>

      {/* Shared Media */}
      <SharedMedia />
    </div>
  );
}
