let audioCtx = null;

/**
 * AudioContext-ni yaratish yoki mavjudini qaytarish.
 * Brauzer cheklovlari tufayli u doim 'suspended' holatda boshlanishi mumkin.
 */
function getOrCreateContext() {
  if (!audioCtx || audioCtx.state === "closed") {
    audioCtx = new (window.AudioContext || window.webkitAudioContext)();
  }
  return audioCtx;
}

/**
 * Foydalanuvchi biror amal bajarganda (click, touch) audioni faollashtirish.
 * Bu funksiyani App.jsx yoki asosiy sahifada bitta "Click" eventiga bog'lab qo'yish shart.
 */
export async function initAudio() {
  const ctx = getOrCreateContext();
  if (ctx.state === "suspended") {
    try {
      await ctx.resume();
    } catch (e) {
      console.warn("AudioContext-ni faollashtirib bo'lmadi:", e);
    }
  }
}

function isSoundEnabled() {
  return localStorage.getItem("app_notif_sound") !== "false";
}

/**
 * Umumiy oscillator yaratuvchi yordamchi funksiya.
 * Har bir tovush tugagach, resurslarni avtomatik tozalaydi.
 */
function playTone(freq, type, duration, volume, startTime = 0) {
  const ctx = getOrCreateContext();
  if (ctx.state !== "running" || !isSoundEnabled()) return null;

  const osc = ctx.createOscillator();
  const gain = ctx.createGain();

  osc.connect(gain);
  gain.connect(ctx.destination);

  osc.type = type;
  const now = ctx.currentTime + startTime;

  // Chastotani sozlash
  if (Array.isArray(freq)) {
    // Agar chastota massiv bo'lsa, vaqt o'tishi bilan o'zgaradi (slide effect)
    osc.frequency.setValueAtTime(freq[0], now);
    osc.frequency.exponentialRampToValueAtTime(freq[1], now + duration);
  } else {
    osc.frequency.setValueAtTime(freq, now);
  }

  // Ovoz balandligini sozlash (yumshoq boshlanish va tugash)
  gain.gain.setValueAtTime(volume, now);
  gain.gain.exponentialRampToValueAtTime(0.01, now + duration);

  osc.start(now);
  osc.stop(now + duration);

  return { osc, gain };
}

// 1. Yangi xabar ovozi (Qisqa va mayin "ding")
export function playMessageSound() {
  // 880Hz dan 1200Hz ga tez ko'tariluvchi tovush
  playTone([880, 1200], "sine", 0.3, 0.2);
}

// 2. Qo'ng'iroq tugashi (Uchta qisqa past chastotali beep)
export function playCallEnd() {
  for (let i = 0; i < 3; i++) {
    playTone(440, "sine", 0.15, 0.2, i * 0.2);
  }
}

// 3. Kiruvchi qo'ng'iroq (Ringtone)
export function playRingtone() {
  if (!isSoundEnabled()) return { stop: () => {} };

  let isPlaying = true;
  let nextRingTimeout = null;

  const ring = () => {
    if (!isPlaying) return;

    // Telefon jiringlashi simulyatsiyasi (ikki xil nota)
    playTone(523.25, "sine", 0.2, 0.3, 0);     // C5
    playTone(659.25, "sine", 0.25, 0.3, 0.25); // E5

    nextRingTimeout = setTimeout(ring, 2000);
  };

  // Birinchi jiringlashni boshlash
  // Context 'suspended' bo'lsa, resume qilib keyin boshlaymiz
  const ctx = getOrCreateContext();
  if (ctx.state === "suspended") {
    ctx.resume().then(ring);
  } else {
    ring();
  }

  return {
    stop: () => {
      isPlaying = false;
      if (nextRingTimeout) clearTimeout(nextRingTimeout);
    },
  };
}