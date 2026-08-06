import fs from "fs";
import path from "path";
import {
  pool,
  USERS_TABLE,
  MESSAGES_TABLE,
  GROUP_MESSAGES_TABLE,
  CHANNEL_MESSAGES_TABLE,
} from "./database.js";

const UPLOADS_DIR = "uploads";
const DEFAULT_TTL_HOURS = 24;
const DEFAULT_INTERVAL_MINUTES = 60;

/**
 * Serverda xabar va fayllar faqat vaqtincha turadi: qurilmaga yetkazish uchun
 * yetarli muddat, undan keyin o'chiriladi. Doimiy nusxa — foydalanuvchi
 * telefonida.
 *
 * MUHIM: bu ish klient xabarlarni o'zida saqlay boshlagandan keyingina
 * yoqilishi kerak. Shuning uchun standart holatda O'CHIQ — yoqish uchun
 * MESSAGE_TTL_ENABLED=true qo'yiladi. Aks holda 24 soatdan keyin tarix
 * hech qayerda qolmaydi.
 */
function getConfig() {
  const enabled = String(process.env.MESSAGE_TTL_ENABLED || "").trim() === "true";
  const ttlHours = Number(process.env.MESSAGE_TTL_HOURS) || DEFAULT_TTL_HOURS;
  const intervalMinutes =
    Number(process.env.MESSAGE_TTL_INTERVAL_MINUTES) || DEFAULT_INTERVAL_MINUTES;
  return { enabled, ttlHours, intervalMinutes };
}

/**
 * Qo'ng'iroq yozuvlari xabar jadvalida "__CALL:audio:143__" ko'rinishida
 * saqlanadi va Qo'ng'iroqlar sahifasi aynan shulardan quriladi. Ular bir
 * necha bayt matn — media ham, ilova ham yo'q — shuning uchun tozalashdan
 * chetda qoladi: aks holda tarix 24 soatdan keyin bo'shab qolardi.
 *
 * LIKE emas, regexp ishlatilgan: LIKE da '_' bitta belgini almashtiradi va
 * '__CALL:%' tasodifiy matnlarga ham tushib qolardi.
 */
const KEEP_CALL_LOGS = `(content IS NULL OR content !~ '^__CALL:')`;

async function purgeMessages(ttlHours) {
  const cutoff = `${ttlHours} hours`;
  const tables = [MESSAGES_TABLE, GROUP_MESSAGES_TABLE, CHANNEL_MESSAGES_TABLE];
  let total = 0;
  for (const table of tables) {
    try {
      // Qo'ng'iroqlar faqat shaxsiy chatlarda bo'ladi.
      const keepCalls = table === MESSAGES_TABLE ? `AND ${KEEP_CALL_LOGS}` : '';
      const res = await pool.query(
        `DELETE FROM ${table}
         WHERE created_at < NOW() - $1::interval ${keepCalls}`,
        [cutoff]
      );
      if (res.rowCount > 0) {
        console.log(`[TTL] ${table}: ${res.rowCount} ta xabar o'chirildi`);
        total += res.rowCount;
      }
    } catch (e) {
      console.error(`[TTL] ${table} tozalashda xato:`, e.message);
    }
  }
  return total;
}

/**
 * Hali ishlatilayotgan fayllar ro'yxati: avatarlar (ular xabar emas, muddatsiz
 * turadi) va TTL ichidagi xabarlarga biriktirilgan media.
 */
async function collectReferencedFiles() {
  const referenced = new Set();
  const queries = [
    `SELECT avatar AS f FROM ${USERS_TABLE} WHERE avatar IS NOT NULL`,
    `SELECT image AS f FROM ${MESSAGES_TABLE} WHERE image IS NOT NULL
     UNION ALL SELECT audio FROM ${MESSAGES_TABLE} WHERE audio IS NOT NULL
     UNION ALL SELECT video FROM ${MESSAGES_TABLE} WHERE video IS NOT NULL`,
    `SELECT image AS f FROM ${GROUP_MESSAGES_TABLE} WHERE image IS NOT NULL
     UNION ALL SELECT audio FROM ${GROUP_MESSAGES_TABLE} WHERE audio IS NOT NULL`,
    `SELECT image AS f FROM ${CHANNEL_MESSAGES_TABLE} WHERE image IS NOT NULL
     UNION ALL SELECT audio FROM ${CHANNEL_MESSAGES_TABLE} WHERE audio IS NOT NULL`,
  ];
  for (const sql of queries) {
    try {
      const { rows } = await pool.query(sql);
      for (const row of rows) {
        if (row.f) referenced.add(path.basename(String(row.f)));
      }
    } catch (e) {
      // Jadval yo'q bo'lishi mumkin (masalan guruhlar ishlatilmasa) — bu
      // holda faylni "ishlatilmayapti" deb hisoblamaymiz, xavfsiz tomonni
      // tanlab, tozalashni umuman to'xtatamiz.
      console.error("[TTL] fayl havolalarini yig'ishda xato:", e.message);
      return null;
    }
  }
  return referenced;
}

async function purgeUploads(ttlHours) {
  if (!fs.existsSync(UPLOADS_DIR)) return 0;

  const referenced = await collectReferencedFiles();
  if (referenced === null) {
    console.warn("[TTL] havolalar ro'yxati olinmadi — fayllar tozalanmadi");
    return 0;
  }

  const now = Date.now();
  const maxAge = ttlHours * 60 * 60 * 1000;
  let deleted = 0;

  for (const file of fs.readdirSync(UPLOADS_DIR)) {
    // Avatar yoki hali tirik xabarga tegishli fayl — qoladi.
    if (referenced.has(file)) continue;
    const filePath = path.join(UPLOADS_DIR, file);
    try {
      const stat = fs.statSync(filePath);
      if (!stat.isFile()) continue;
      // Yangi yuklangan, lekin hali xabarga biriktirilmagan fayl o'chib
      // ketmasligi uchun yosh ham tekshiriladi.
      if (now - stat.mtimeMs <= maxAge) continue;
      fs.unlinkSync(filePath);
      deleted++;
    } catch (e) {
      console.error(`[TTL] ${file} o'chirishda xato:`, e.message);
    }
  }

  if (deleted > 0) console.log(`[TTL] ${deleted} ta yetim fayl o'chirildi`);
  return deleted;
}

export async function runRetentionOnce(ttlHours) {
  const messages = await purgeMessages(ttlHours);
  const files = await purgeUploads(ttlHours);
  return { messages, files };
}

export function startRetentionScheduler() {
  const { enabled, ttlHours, intervalMinutes } = getConfig();

  if (!enabled) {
    console.log(
      "[TTL] Xabar saqlash muddati o'chirilgan. Yoqish uchun MESSAGE_TTL_ENABLED=true " +
        "(faqat klient xabarlarni o'zida saqlaydigan versiyaga o'tgandan keyin!)",
    );
    return;
  }

  const tick = () => {
    runRetentionOnce(ttlHours).catch((e) =>
      console.error("[TTL] tozalashda xato:", e.message),
    );
  };

  tick();
  setInterval(tick, intervalMinutes * 60 * 1000);
  console.log(
    `[TTL] Har ${intervalMinutes} daqiqada ${ttlHours} soatdan eski xabar va fayllar o'chiriladi`,
  );
}
