import { readFileSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const KEY_PATH = join(__dirname, '../../firebase-service-account.json');

let messaging = null;

if (existsSync(KEY_PATH)) {
  try {
    const { default: admin } = await import('firebase-admin');
    const serviceAccount = JSON.parse(readFileSync(KEY_PATH, 'utf8'));
    if (!admin.apps.length) {
      admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
    }
    messaging = admin.messaging();
    console.log('[FCM] Firebase Admin initialized');
  } catch (e) {
    console.error('[FCM] init error:', e.message);
  }
} else {
  console.warn('[FCM] firebase-service-account.json topilmadi — FCM o\'chirildi');
}

export async function sendCallFcm(token, { callerName, isVideo, callId }) {
  if (!messaging || !token) return false;
  try {
    // Data-only + high priority: battery optimization o'chirilgan qurilmada
    // onBackgroundMessage ishga tushadi → showCallkitIncoming() → to'liq ekranli CallKit.
    await messaging.send({
      token,
      android: {
        priority: 'high',
        ttl: 60000,
      },
      data: {
        type: 'incoming_call',
        callId: String(callId),
        callerName: String(callerName),
        isVideo: isVideo ? 'true' : 'false',
      },
    });
    return true;
  } catch (e) {
    const code = e?.errorInfo?.code ?? '';
    if (
      code === 'messaging/registration-token-not-registered' ||
      code === 'messaging/invalid-registration-token'
    ) {
      return 'expired';
    }
    console.error('[FCM] send error:', e.message);
    return false;
  }
}
