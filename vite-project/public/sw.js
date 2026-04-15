// Bootchat Service Worker — Push Notifications

self.addEventListener("push", (event) => {
  let data = { title: "Bootchat", body: "Yangi xabar", type: "message" };

  if (event.data) {
    try {
      data = event.data.json();
    } catch {
      data.body = event.data.text();
    }
  }

  const options = {
    body: data.body,
    icon: "/bootchat-logo.png",
    badge: "/bootchat-logo.png",
    tag: data.tag || "bootchat-notification",
    data: { url: data.url || "/" },
    vibrate: [200, 100, 200],
  };

  event.waitUntil(self.registration.showNotification(data.title, options));
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();

  const url = event.notification.data?.url || "/";

  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true }).then((windowClients) => {
      // Ochiq tab bormi?
      for (const client of windowClients) {
        if (client.url.includes(self.location.origin) && "focus" in client) {
          return client.focus();
        }
      }
      // Yangi tab ochish
      return clients.openWindow(url);
    })
  );
});
