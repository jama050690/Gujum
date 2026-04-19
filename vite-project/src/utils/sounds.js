let audioCtx = null;
let audioUnlocked = false;

export function initAudio() {
  if (!audioCtx) {
    audioCtx = new (window.AudioContext || window.webkitAudioContext)();
  }
  if (audioCtx.state === "running") {
    audioUnlocked = true;
    return;
  }
  if (audioCtx.state === "suspended") {
    audioCtx
      .resume()
      .then(() => {
        audioUnlocked = true;
      })
      .catch(() => {
        audioUnlocked = false;
      });
  }
}

function getAudioContext() {
  if (!audioUnlocked) return null;

  if (!audioCtx || audioCtx.state === "closed") {
    audioCtx = new (window.AudioContext || window.webkitAudioContext)();
  }
  if (audioCtx.state === "suspended") {
    return null;
  }
  return audioCtx;
}

function isSoundEnabled() {
  return localStorage.getItem("app_notif_sound") !== "false";
}

// Yangi xabar ovozi — qisqa "ding"
export function playMessageSound() {
  if (!isSoundEnabled()) return;
  try {
    const ctx = getAudioContext();
    if (!ctx) return;
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();

    osc.connect(gain);
    gain.connect(ctx.destination);

    osc.type = "sine";
    osc.frequency.setValueAtTime(880, ctx.currentTime);
    osc.frequency.setValueAtTime(1200, ctx.currentTime + 0.08);

    gain.gain.setValueAtTime(0.3, ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.01, ctx.currentTime + 0.3);

    osc.start(ctx.currentTime);
    osc.stop(ctx.currentTime + 0.3);
  } catch (e) {
    console.warn("Message sound error:", e);
  }
}

// Qo'ng'iroq tugashi ovozi — "beep beep"
export function playCallEnd() {
  if (!isSoundEnabled()) return;
  try {
    const ctx = getAudioContext();
    if (!ctx) return;

    for (let i = 0; i < 3; i++) {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.connect(gain);
      gain.connect(ctx.destination);

      osc.type = "sine";
      osc.frequency.value = 480;

      const start = ctx.currentTime + i * 0.2;
      gain.gain.setValueAtTime(0.25, start);
      gain.gain.exponentialRampToValueAtTime(0.01, start + 0.12);

      osc.start(start);
      osc.stop(start + 0.12);
    }
  } catch (e) {
    console.warn("Call end sound error:", e);
  }
}

// Kiruvchi qo'ng'iroq — takrorlanuvchi ringtone
// stop() methodi qaytaradi
export function playRingtone() {
  if (!isSoundEnabled()) return { stop: () => { } };

  let stopped = false;
  let timeoutId = null;

  function ring() {
    if (stopped) return;
    try {
      const ctx = getAudioContext();
      if (!ctx) return;

      // Ring pattern: 2 ta qisqa beep
      for (let i = 0; i < 2; i++) {
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        osc.connect(gain);
        gain.connect(ctx.destination);

        osc.type = "sine";
        osc.frequency.value = i === 0 ? 440 : 520;

        const start = ctx.currentTime + i * 0.25;
        gain.gain.setValueAtTime(0.3, start);
        gain.gain.exponentialRampToValueAtTime(0.01, start + 0.2);

        osc.start(start);
        osc.stop(start + 0.2);
      }

      // 2 sekunddan keyin qayta ring
      timeoutId = setTimeout(ring, 2000);
    } catch (e) {
      console.warn("Ringtone error:", e);
    }
  }

  ring();

  return {
    stop: () => {
      stopped = true;
      if (timeoutId) clearTimeout(timeoutId);
    },
  };
}
