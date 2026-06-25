import { readFileSync, existsSync } from 'fs';
import { unlink } from 'fs/promises';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const KEY_PATH = join(__dirname, '../../firebase-service-account.json');

const UNSAFE = new Set(['LIKELY', 'VERY_LIKELY']);
let _cred = null;

async function _getCred() {
  if (_cred) return _cred;
  if (!existsSync(KEY_PATH)) return null;
  try {
    const { default: admin } = await import('firebase-admin');
    const sa = JSON.parse(readFileSync(KEY_PATH, 'utf8'));
    if (!admin.apps.length) {
      admin.initializeApp({ credential: admin.credential.cert(sa) });
    }
    _cred = admin.app().options.credential;
    return _cred;
  } catch { return null; }
}

async function checkImageSafety(filePath) {
  try {
    const cred = await _getCred();
    if (!cred) return { safe: true };
    const { access_token } = await cred.getAccessToken();
    const base64 = readFileSync(filePath).toString('base64');
    const res = await fetch('https://vision.googleapis.com/v1/images:annotate', {
      method: 'POST',
      headers: { Authorization: `Bearer ${access_token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        requests: [{ image: { content: base64 }, features: [{ type: 'SAFE_SEARCH_DETECTION' }] }],
      }),
    });
    const data = await res.json();
    const s = data.responses?.[0]?.safeSearchAnnotation;
    if (!s) return { safe: true };
    if (UNSAFE.has(s.adult)) return { safe: false, reason: 'axloqsiz' };
    if (UNSAFE.has(s.violence)) return { safe: false, reason: "zo'rovon" };
    if (s.racy === 'VERY_LIKELY') return { safe: false, reason: 'uyatli' };
    return { safe: true };
  } catch (e) {
    console.error('[ContentFilter] Vision API xato:', e.message);
    return { safe: true };
  }
}

export async function imageContentCheck(req, res, next) {
  if (!req.file) return next();
  if (!req.file.mimetype.startsWith('image/')) {
    await unlink(req.file.path).catch(() => {});
    return res.status(400).json({ message: "Noto'g'ri fayl turi" });
  }
  const { safe, reason } = await checkImageSafety(req.file.path);
  if (!safe) {
    await unlink(req.file.path).catch(() => {});
    return res.status(400).json({ message: `Bu rasm qabul qilinmadi: ${reason} kontent aniqlandi` });
  }
  next();
}

export async function videoContentCheck(req, res, next) {
  if (!req.file) return next();
  if (!req.file.mimetype.startsWith('video/')) {
    await unlink(req.file.path).catch(() => {});
    return res.status(400).json({ message: "Noto'g'ri fayl turi: video kerak" });
  }
  next();
}
