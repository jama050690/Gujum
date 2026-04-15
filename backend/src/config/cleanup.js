import fs from "fs";
import path from "path";

const UPLOADS_DIR = "uploads";
const MAX_AGE_DAYS = 7;
const INTERVAL_HOURS = 6;

const VIDEO_EXTENSIONS = [".mp4", ".mov", ".avi", ".webm", ".mkv", ".3gp"];

function cleanOldVideos() {
  if (!fs.existsSync(UPLOADS_DIR)) return;

  const now = Date.now();
  const maxAge = MAX_AGE_DAYS * 24 * 60 * 60 * 1000;
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
  // Dastlab bir marta tekshirish
  cleanOldVideos();

  // Har 6 soatda tekshirish
  setInterval(cleanOldVideos, INTERVAL_HOURS * 60 * 60 * 1000);
  console.log(`Video tozalash: har ${INTERVAL_HOURS} soatda, ${MAX_AGE_DAYS} kundan eski videolar o'chiriladi`);
}
