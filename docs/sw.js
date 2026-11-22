// Comp-Planer: Seite und Daten immer frisch aus dem Netz, offline die letzte Version.
const C = "planer-v1";
self.addEventListener("install", e => self.skipWaiting());
self.addEventListener("activate", e => e.waitUntil(clients.claim()));
self.addEventListener("fetch", e => {
  const r = e.request;
  if (r.method !== "GET" || new URL(r.url).origin !== location.origin) return;
  const isIcon = /\/icons\/|app-\d+\.png|og\.jpg/.test(r.url);
  if (isIcon) {
    e.respondWith(caches.open(C).then(c => c.match(r).then(hit => hit || fetch(r).then(res => { if (res.ok) c.put(r, res.clone()); return res; }))));
    return;
  }
  e.respondWith(fetch(r).then(res => { if (res.ok) caches.open(C).then(c => c.put(r, res.clone())); return res; })
    .catch(() => caches.match(r).then(hit => hit || caches.match("./"))));
});
