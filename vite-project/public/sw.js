// Bootchat Service Worker — Push Notifications & Calling Support

self.addEventListener("push", (event) => {
  let data = { 
    title: "Bootchat", 
    body: "Yangi bildirishnoma", 
    type: "message" 
  };

  if (event.data) {
    try {
      data = event.data.json();
    } catch (e) {
      data.body = event.data.text();
    }
  }

  // Qo'ng'iroq va oddiy xabarlar uchun alohida sozlamalar
  const isCall = data.type === "CALL_OFFER";
  
  const options = {
    body: data.body,
    icon: "/bootchat/favicon.ico", // Pathni loyihangizga qarab tekshiring
    badge: "/bootchat/favicon.ico",
    tag: data.tag || (isCall ? "incoming-call" : "bootchat-notification"),
    data: { 
      url: data.url || "/bootchat/",
      type: data.type 
    },
    // Qo'ng'iroq bo'lsa uzoqroq va kuchliroq vibratsiya
    vibrate: isCall ? [500, 200, 500, 200, 500, 200, 500] : [200, 100, 200],
    // Qo'ng'iroq bo'lsa foydalanuvchi javob bermaguncha bildirishnoma turadi
    requireInteraction: isCall, 
    renotify: true,
  };

  // Agar bu qo'ng'iroq bo'lsa, tugmalarni qo'shamiz
  if (isCall) {
    options.actions = [
      { action: "answer", title: "✅ Javob berish" },
      { action: "reject", title: "❌ Rad etish" }
    ];
  }

  event.waitUntil(
    self.registration.showNotification(data.title || "Bootchat", options)
  );
});

// Bildirishnoma bosilganda (yoki tugmalari bosilganda)
self.addEventListener("notificationclick", (event) => {
  event.notification.close();

  const url = event.notification.data?.url || "/bootchat/";
  const action = event.action;

  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true }).then((windowClients) => {
      // 1. Agar sayt ochiq bo'lsa, o'shanga fokus qilish
      for (const client of windowClients) {
        if (client.url.indexOf(url) !== -1 && "focus" in client) {
          if (action === "reject") return; // Rad etilsa shunchaki yopamiz
          return client.focus();
        }
      }
      // 2. Agar sayt yopiq bo'lsa, yangi tabda ochish
      if (action !== "reject" && clients.openWindow) {
        return clients.openWindow(url);
      }
    })
  );
});