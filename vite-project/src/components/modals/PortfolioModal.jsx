import { useAuth } from "@/context/AuthContext";
import { useLanguage } from "@/context/LanguageContext";
import { getProfileData } from "@/utils/storage";
import Avatar from "@/components/common/Avatar";
import Modal from "./Modal";

export default function PortfolioModal({ isOpen, onClose, onEdit }) {
  const { user, avatar } = useAuth();
  const { t } = useLanguage();
  const profile = getProfileData();
  const fallbackValue = t("common_not_specified");

  return (
    <Modal isOpen={isOpen} onClose={onClose} title={t("portfolio_title")}>
      <div className="p-5">
        <div className="flex flex-col items-center text-center mb-6">
          <Avatar src={avatar} name={user} size={80} />
          <h3 className="text-xl font-bold text-gray-900 dark:text-white mt-3">{user}</h3>
          <p className="text-sm text-gray-400">{t("online")}</p>
        </div>

        <div className="space-y-3">
          <div className="flex items-center gap-3 p-3 bg-gray-50 dark:bg-gray-800 rounded-xl">
            <i className="fas fa-phone text-blue-500 w-5 text-center" />
            <div>
              <p className="text-xs text-gray-400">{t("settings_phone")}</p>
              <p className="text-sm text-gray-900 dark:text-white">{profile.phone || fallbackValue}</p>
            </div>
          </div>
          <div className="flex items-center gap-3 p-3 bg-gray-50 dark:bg-gray-800 rounded-xl">
            <i className="fas fa-at text-blue-500 w-5 text-center" />
            <div>
              <p className="text-xs text-gray-400">{t("settings_username")}</p>
              <p className="text-sm text-gray-900 dark:text-white">@{user}</p>
            </div>
          </div>
          <div className="flex items-center gap-3 p-3 bg-gray-50 dark:bg-gray-800 rounded-xl">
            <i className="fas fa-birthday-cake text-blue-500 w-5 text-center" />
            <div>
              <p className="text-xs text-gray-400">{t("settings_birthday")}</p>
              <p className="text-sm text-gray-900 dark:text-white">{profile.birthday || fallbackValue}</p>
            </div>
          </div>
        </div>

        <button
          onClick={onEdit}
          className="w-full mt-6 py-3 bg-blue-500 text-white rounded-xl font-semibold hover:bg-blue-600 transition-colors"
        >
          <i className="fas fa-edit mr-2" />{t("edit_profile_title")}
        </button>
      </div>
    </Modal>
  );
}
