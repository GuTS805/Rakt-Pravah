/**
 * Rakt Pravah - Firebase Cloud Messaging Service Worker
 * Handles background push notifications when the web app is closed or in background.
 */

importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyA2yFoOysPx0w1zkV991xIC0nWiFP0Ersk',
  appId: '1:458287363105:web:09a1f9af7fc04b6d005f60',
  messagingSenderId: '458287363105',
  projectId: 'nobloodlink',
  authDomain: 'nobloodlink.firebaseapp.com',
  storageBucket: 'nobloodlink.firebasestorage.app',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Background message received: ', payload);
  
  const title = payload.notification?.title || payload.data?.title || '🩸 Urgent Blood Request';
  const options = {
    body: payload.notification?.body || payload.data?.body || 'A patient urgently needs blood near your location.',
    icon: '/icons/Icon-192.png',
    badge: '/favicon.png',
    vibrate: [200, 100, 200],
    data: payload.data || {},
    actions: [
      {
        action: 'view_request',
        title: 'View Request',
      },
    ],
  };

  return self.registration.showNotification(title, options);
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const data = event.notification.data || {};
  const requestId = data.requestId;
  const targetUrl = requestId ? `/#/invitations/${requestId}` : '/';

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windowClients) => {
      for (let client of windowClients) {
        if ('focus' in client) {
          if (client.url.includes(self.location.origin)) {
            client.navigate(targetUrl);
            return client.focus();
          }
        }
      }
      if (clients.openWindow) {
        return clients.openWindow(targetUrl);
      }
    })
  );
});
