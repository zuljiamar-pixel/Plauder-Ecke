/* Plauderecke: zeigt Benachrichtigungen an, auch wenn die Seite zu ist */
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(self.clients.claim()));

self.addEventListener('push', e => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch { d = { body: e.data ? e.data.text() : '' }; }
  e.waitUntil((async () => {
    // Is Plauderecke on the screen right now? Then the chat itself shows the message.
    // ("focused" is not reliable for apps added to the home screen, so being visible is enough.)
    const wins = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    if (wins.some(w => w.visibilityState === 'visible')) return;
    await self.registration.showNotification(d.title || 'Plauderecke', {
      body: d.body || 'Neue Nachricht',
      tag: d.group || 'plauderecke',
      renotify: true,
      icon: 'icon-192.png',
      badge: 'badge-96.png',
      data: { group: d.group || null },
    });
  })());
});

self.addEventListener('notificationclick', e => {
  e.notification.close();
  const group = e.notification.data && e.notification.data.group;
  const url = new URL(group ? './#g=' + group : './', self.registration.scope).href;
  e.waitUntil((async () => {
    const wins = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const w of wins){
      if ('focus' in w){ await w.focus(); w.postMessage({ openGroup: group }); return; }
    }
    await self.clients.openWindow(url);
  })());
});
