import { getInitials, getAvatarColor } from "@/utils/formatters";
import { getBaseUrl } from "@/utils/api";
import { resolveMediaUrl } from "@/utils/media";

const NO_PROFILE = `${import.meta.env.BASE_URL}images/no_profile_picture.webp`;

export default function Avatar({ src, name, size = 40, online, className = "" }) {
  const sizeClass = `w-[${size}px] h-[${size}px]`;
  const initials = getInitials(name);
  const bgColor = getAvatarColor(name);

  const imgSrc = (() => {
    if (!src) return null;
    if (src.startsWith("http") || src.startsWith("data:") || src.startsWith(import.meta.env.BASE_URL + "images")) return src;
    return resolveMediaUrl(src, getBaseUrl());
  })();

  return (
    <div className={`relative inline-flex shrink-0 ${className}`}>
      {imgSrc ? (
        <img
          src={imgSrc}
          alt={name}
          onError={(e) => { e.target.src = NO_PROFILE; }}
          className="rounded-full object-cover"
          style={{ width: size, height: size }}
        />
      ) : (
        <div
          className="rounded-full flex items-center justify-center text-white font-bold"
          style={{ width: size, height: size, backgroundColor: bgColor, fontSize: size * 0.4 }}
        >
          {initials}
        </div>
      )}
      {online && (
        <span
          className="absolute bottom-0 right-0 w-3 h-3 rounded-full border-2 border-white bg-green-500"
        />
      )}
    </div>
  );
}
