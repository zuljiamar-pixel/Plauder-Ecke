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
    // A call stays on screen and vibrates longer until it is tapped or swiped away
    const isCall = d.kind === 'call';
    await self.registration.showNotification(d.title || 'Plauderecke', {
      body: d.body || 'Neue Nachricht',
      tag: isCall ? 'call-' + (d.group || '') : (d.group || 'plauderecke'),
      renotify: true,
      requireInteraction: isCall,
      vibrate: isCall ? [500, 250, 500, 250, 500, 250, 500] : [200],
      icon: 'icon-192.png',
      badge: 'badge-96.png',
      data: { group: d.group || null, call: isCall ? d.id || null : null },
    });
  })());
});

self.addEventListener('notificationclick', e => {
  e.notification.close();
  const group = e.notification.data && e.notification.data.group, call = e.notification.data && e.notification.data.call;
  const url = new URL(group ? './#g=' + group + (call ? '&call=' + call : '') : './', self.registration.scope).href;
  e.waitUntil((async () => {
    const wins = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const w of wins){
      if ('focus' in w){ await w.focus(); w.postMessage({ openGroup: group, call }); return; }
    }
    await self.clients.openWindow(url);
  })());
});
