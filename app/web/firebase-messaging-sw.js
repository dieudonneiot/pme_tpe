// web/firebase-messaging-sw.js

importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js");

// Config Firebase (doit correspondre à DefaultFirebaseOptions.web)
firebase.initializeApp({
  apiKey: "AIzaSyC6MQ_LsqoSKl7iBchO6kMwonhJHbRXvvs",
  authDomain: "com-example-flutter-appli-1.firebaseapp.com",
  projectId: "com-example-flutter-appli-1",
  storageBucket: "com-example-flutter-appli-1.firebasestorage.app",
  messagingSenderId: "433429123250",
  appId: "1:433429123250:web:a9925dcbb53db9747fb9ab",
  measurementId: "G-X7QSSFZT6P",
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const title = (payload.notification && payload.notification.title) ? payload.notification.title : "Notification";
  const body = (payload.notification && payload.notification.body) ? payload.notification.body : "";

  const deepLink = payload.data && payload.data.deep_link ? payload.data.deep_link : null;

  self.registration.showNotification(title, {
    body,
    data: { deep_link: deepLink, ...((payload.data) || {}) },
  });
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const deepLink = event.notification.data && event.notification.data.deep_link;

  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if ("focus" in client) return client.focus();
      }
      if (clients.openWindow) return clients.openWindow(deepLink || "/");
    })
  );
});