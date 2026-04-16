import fs from "fs";
import path from "path";

const UPLOADS_DIR = "uploads";
const DEFAULT_MAX_AGE_DAYS = 0;
const DEFAULT_INTERVAL_HOURS = 6;

const VIDEO_EXTENSIONS = [".mp4", ".mov", ".avi", ".webm", ".mkv", ".3gp"];

function parseNumber(value, fallback) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function getCleanupConfig() {
  const maxAgeDays = parseNumber(
    process.env.UPLOAD_VIDEO_MAX_AGE_DAYS,
    DEFAULT_MAX_AGE_DAYS,
  );
  const intervalHours = parseNumber(
    process.env.UPLOAD_VIDEO_CLEANUP_INTERVAL_HOURS,
    DEFAULT_INTERVAL_HOURS,
  );

  return {
    enabled: maxAgeDays > 0 && intervalHours > 0,
    maxAgeDays,
    intervalHours,
  };
}

function cleanOldVideos(maxAgeDays) {
  if (!fs.existsSync(UPLOADS_DIR)) return;

  const now = Date.now();
  const maxAge = maxAgeDays * 24 * 60 * 60 * 1000;
  let deleted = 0;

  const files = fs.readdirSync(UPLOADS_DIR);
  for (const file of files) {
    const ext = path.extname(file).toLowerCase();
    if (!VIDEO_EXTENSIONS.includes(ext)) continue;

    const filePath = path.join(UPLOADS_DIR, file);
    const stat = fs.statSync(filePath);

    if (now - stat.mtimeMs > maxAge) {
      fs.unlinkSync(filePath);
      deleted++;
      console.log(`Eski video o'chirildi: ${file}`);
    }
  }

  if (deleted > 0) {
    console.log(`Jami ${deleted} ta eski video o'chirildi`);
  }
}

export function startCleanupScheduler() {
  const config = getCleanupConfig();

  if (!config.enabled) {
    console.log(
      "Video tozalash o'chirilgan. Uni yoqish uchun UPLOAD_VIDEO_MAX_AGE_DAYS ni 0 dan katta qiymatga o'rnating.",
    );
    return;
  }

  // Dastlab bir marta tekshirish
  cleanOldVideos(config.maxAgeDays);

  // Har 6 soatda tekshirish
  setInterval(
    () => cleanOldVideos(config.maxAgeDays),
    config.intervalHours * 60 * 60 * 1000,
  );
  console.log(
    `Video tozalash: har ${config.intervalHours} soatda, ${config.maxAgeDays} kundan eski videolar o'chiriladi`,
  );
}
