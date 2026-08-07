import { useRef, useState } from "react";
import { useAuth } from "@/context/AuthContext";
import { useLanguage } from "@/context/LanguageContext";
import { getProfileData, saveProfileData } from "@/utils/storage";
import { BASE_URL } from "@/utils/api";
import Avatar from "@/components/common/Avatar";
import Modal from "./Modal";

export default function EditProfileModal({ isOpen, onClose }) {
  const { user, avatar, fullName, updateAvatar, updateFullName } = useAuth();
  const { t } = useLanguage();
  const profile = getProfileData();
  const [name, setName] = useState(fullName || profile.fullName || "");
  const [bio, setBio] = useState(profile.bio);
  const [phone, setPhone] = useState(profile.phone);
  const [newAvatar, setNewAvatar] = useState(null);
  const [avatarFile, setAvatarFile] = useState(null);
  const dateRef = useRef(null);

  // Birthday: parse stored "YYYY-MM-DD" into separate fields
  const parseBirthday = (val) => {
    if (!val) return { day: "", month: "", year: "" };
    const [y, m, d] = val.split("-");
    return { day: d || "", month: m || "", year: y || "" };
  };
  const [bdayParts, setBdayParts] = useState(() => parseBirthday(profile.birthday));

  const buildBirthday = (parts) => {
    const { day, month, year } = parts;
    if (day && month && year && year.length === 4) {
      return `${year}-${month.padStart(2, "0")}-${day.padStart(2, "0")}`;
    }
    return "";
  };

  const handleBdayChange = (field, value) => {
    const num = value.replace(/\D/g, "");
    let limited = num;
    if (field === "day") limited = num.slice(0, 2);
    if (field === "month") limited = num.slice(0, 2);
    if (field === "year") limited = num.slice(0, 4);
    setBdayParts((prev) => ({ ...prev, [field]: limited }));
  };

  const handleDatePick = (e) => {
    const val = e.target.value;
    if (val) setBdayParts(parseBirthday(val));
  };

  const handleAvatarChange = (e) => {
    const file = e.target.files[0];
    if (!file) return;
    setAvatarFile(file);
    const reader = new FileReader();
    reader.onload = (ev) => setNewAvatar(ev.target.result);
    reader.readAsDataURL(file);
  };

  const handleSave = async () => {
    const birthday = buildBirthday(bdayParts);
    saveProfileData({ fullName: name, phone, birthday, bio });
    updateFullName(name);

    // Darhol lokal avatarni yangilash (tezkor ko'rinish uchun)
    if (newAvatar) updateAvatar(newAvatar);

    // Serverga yuklash
    const formData = new FormData();
    formData.append("full_name", name);
    formData.append("phone", phone);
    formData.append("bio", bio);
    if (birthday) formData.append("birthday", birthday);
    if (avatarFile) formData.append("avatar", avatarFile);

    try {
      const res = await fetch(`${BASE_URL}/api/users/profile`, {
        method: "PUT",
        credentials: "include",
        body: formData,
      });
      if (res.ok) {
        const data = await res.json();
        if (data.avatar) {
          updateAvatar(data.avatar);
        }
      }
    } catch {
      // Lokal avatar allaqachon yangilangan
    }

    onClose();
  };

  return (
    <Modal isOpen={isOpen} onClose={onClose} title={t("edit_profile_title")}>
      <div className="p-5 space-y-4">
        <div className="flex justify-center">
          <label className="relative cursor-pointer">
            <Avatar src={newAvatar || avatar} name={user} size={80} />
            <div className="absolute bottom-0 right-0 w-7 h-7 bg-blue-500 rounded-full flex items-center justify-center border-2 border-white dark:border-gray-900">
              <i className="fas fa-camera text-white text-[10px]" />
            </div>
            <input type="file" accept="image/*" className="hidden" onChange={handleAvatarChange} />
          </label>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">{t("edit_profile_name") || "Name"}</label>
          <input
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder={t("edit_profile_name_placeholder") || "Full name"}
            maxLength={50}
            className="w-full px-4 py-3 border border-gray-300 dark:border-gray-600 rounded-xl outline-none focus:ring-2 focus:ring-blue-500 dark:bg-gray-800 dark:text-white"
          />
        </div>

        <div>
          <label className="flex justify-between text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            <span>{t("edit_profile_bio") || "Bio"}</span>
            <span className="text-gray-400 font-normal">{bio.length}/70</span>
          </label>
          <textarea
            value={bio}
            onChange={(e) => e.target.value.length <= 70 && setBio(e.target.value)}
            placeholder={t("edit_profile_bio_placeholder") || "Any details such as age, occupation or city"}
            rows={2}
            className="w-full px-4 py-3 border border-gray-300 dark:border-gray-600 rounded-xl outline-none focus:ring-2 focus:ring-blue-500 dark:bg-gray-800 dark:text-white resize-none"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Username</label>
          <input
            type="text"
            value={user}
            disabled
            className="w-full px-4 py-3 bg-gray-100 dark:bg-gray-800 rounded-xl text-sm text-gray-500 dark:text-gray-400"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">{t("edit_profile_phone")}</label>
          <input
            type="tel"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
            placeholder="+998 XX XXX XX XX"
            className="w-full px-4 py-3 border border-gray-300 dark:border-gray-600 rounded-xl outline-none focus:ring-2 focus:ring-blue-500 dark:bg-gray-800 dark:text-white"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">{t("edit_profile_birthday")}</label>
          <div className="flex gap-2 items-center">
            <input
              type="text"
              inputMode="numeric"
              value={bdayParts.day}
              onChange={(e) => handleBdayChange("day", e.target.value)}
              placeholder="KK"
              maxLength={2}
              className="w-1/5 px-3 py-3 border border-gray-300 dark:border-gray-600 rounded-xl outline-none focus:ring-2 focus:ring-blue-500 dark:bg-gray-800 dark:text-white text-center"
            />
            <input
              type="text"
              inputMode="numeric"
              value={bdayParts.month}
              onChange={(e) => handleBdayChange("month", e.target.value)}
              placeholder="OO"
              maxLength={2}
              className="w-1/5 px-3 py-3 border border-gray-300 dark:border-gray-600 rounded-xl outline-none focus:ring-2 focus:ring-blue-500 dark:bg-gray-800 dark:text-white text-center"
            />
            <input
              type="text"
              inputMode="numeric"
              value={bdayParts.year}
              onChange={(e) => handleBdayChange("year", e.target.value)}
              placeholder="YYYY"
              maxLength={4}
              className="w-2/5 px-3 py-3 border border-gray-300 dark:border-gray-600 rounded-xl outline-none focus:ring-2 focus:ring-blue-500 dark:bg-gray-800 dark:text-white text-center"
            />
            <div className="relative w-1/5">
              <button
                type="button"
                onClick={() => dateRef.current?.showPicker()}
                className="w-full py-3 border border-gray-300 dark:border-gray-600 rounded-xl hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors"
              >
                <i className="fas fa-calendar-alt text-gray-500 dark:text-gray-400" />
              </button>
              <input
                ref={dateRef}
                type="date"
                value={buildBirthday(bdayParts)}
                onChange={handleDatePick}
                className="absolute inset-0 opacity-0 pointer-events-none"
              />
            </div>
          </div>
        </div>

        <button
          onClick={handleSave}
          className="w-full py-3 bg-blue-500 text-white rounded-xl font-semibold hover:bg-blue-600 transition-colors"
        >
          {t("save")}
        </button>
      </div>
    </Modal>
  );
}
