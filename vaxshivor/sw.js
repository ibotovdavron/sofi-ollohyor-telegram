// Vaxshivor ilovasi: internet bo‘lmaganda ham sahifa ochilishi uchun.
const CACHE = "vaxshivor-v7";
const SHELL = ["./", "./index.html", "./manifest.webmanifest", "./icons/icon-192.png", "./icons/icon-512.png"];

self.addEventListener("install", event => {
  event.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", event => {
  const req = event.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);

  // Baza va kirish so‘rovlari hech qachon keshlanmaydi.
  if (url.hostname.endsWith("supabase.co") || url.hostname.endsWith("google.com")) return;

  // Avval internetdan olamiz (yangi versiya darhol ko‘rinadi), bo‘lmasa keshdan.
  event.respondWith(
    fetch(req)
      .then(res => {
        if (res.ok && (url.origin === location.origin || url.hostname === "cdn.jsdelivr.net")) {
          const copy = res.clone();
          caches.open(CACHE).then(c => c.put(req, copy));
        }
        return res;
      })
      .catch(() => caches.match(req, { ignoreSearch: req.mode === "navigate" })
        .then(hit => hit || (req.mode === "navigate" ? caches.match("./index.html") : Response.error())))
  );
});
