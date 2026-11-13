// Service worker mínimo: muestra las notificaciones (Android Chrome no
// permite hacerlo sin uno), recibe el recordatorio de las 6 p. m. que manda
// el servidor aunque la app esté cerrada (Web Push) y abre o enfoca la app
// al tocarlas.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

self.addEventListener('push', (event) => {
  let datos = {};
  try {
    datos = event.data ? event.data.json() : {};
  } catch (_) {
    datos = { cuerpo: event.data ? event.data.text() : '' };
  }
  const titulo = datos.titulo || 'RPA · IPESA';
  event.waitUntil(
    self.registration.showNotification(titulo, {
      body: datos.cuerpo || 'Tienes tareas por cerrar.',
      icon: 'icons/rpa-192.png',
      badge: 'icons/rpa-192.png',
      tag: datos.tag || 'ipesa-recordatorio',
      renotify: true,
      // Que suene y vibre, y se quede hasta que lo vea.
      silent: false,
      requireInteraction: true,
      vibrate: [300, 150, 300, 150, 300],
    }),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((ventanas) => {
      for (const ventana of ventanas) {
        if ('focus' in ventana) return ventana.focus();
      }
      return self.clients.openWindow('./');
    }),
  );
});
