'use strict';
// mq-offline-sw
//
// «مرافق التلميذ» — offline service worker (ours, not Flutter's).
//
// Current Flutter no longer ships a caching service worker (its
// flutter_service_worker.js is only a clean-up stub), so the app could never
// open without internet. This worker keeps the app on the device:
//   * install: stores every file of the build (list written at build time by
//     tools/make_offline_worker.py) so even the first visit works offline later;
//   * every request to this site: NETWORK FIRST (a new deploy is picked up at
//     once; the saved copy is refreshed each time), and when the network is
//     missing / slow / failing the SAVED COPY is served;
//   * Google's CDN files (CanvasKit, fonts): cache first (their URLs carry the
//     engine version, so a saved copy can never be the wrong one);
//   * everything else (Supabase, other sites, POST) is NOT touched.
// The student's data lives in the browser's own storage, never in this cache,
// so updating the app never signs anyone out or erases anything.
//
// In the repository this file is a TEMPLATE. The deploy workflow copies it over
// build/web/flutter_service_worker.js after filling BUILD and PRECACHE.

const BUILD = 'df031614f07b0e7e';
const CACHE = 'mq-app-v1';
const PRECACHE = ["","about/","about/index.html","assets/AssetManifest.bin","assets/AssetManifest.bin.json","assets/FontManifest.json","assets/NOTICES","assets/fonts/MaterialIcons-Regular.otf","assets/fonts/fallback/Roboto-Regular.ttf","assets/shaders/ink_sparkle.frag","assets/shaders/stretch_effect.frag","canvaskit/canvaskit.js","canvaskit/canvaskit.js.symbols","canvaskit/canvaskit.wasm","canvaskit/chromium/canvaskit.js","canvaskit/chromium/canvaskit.js.symbols","canvaskit/chromium/canvaskit.wasm","canvaskit/webparagraph/canvaskit.js","canvaskit/webparagraph/canvaskit.js.symbols","canvaskit/webparagraph/canvaskit.wasm","canvaskit/wimp.js","canvaskit/wimp.js.symbols","canvaskit/wimp.wasm","diagnose_database.html","drift_worker.js","favicon.png","flutter.js","flutter_bootstrap.js","icons/Icon-192.png","icons/Icon-512.png","icons/Icon-maskable-192.png","icons/Icon-maskable-512.png","index.html","main.dart.js","manifest.json","probe.html","robots.txt","sitemap.xml","sqlite3.wasm","teacher/","teacher/index.html","version.json"];
const CDN_HOSTS = ['www.gstatic.com', 'fonts.gstatic.com', 'fonts.googleapis.com'];
const NETWORK_WAIT_MS = 5000;
const SCOPE = self.registration.scope; // ends with '/'
const TIMEOUT = { timeout: true };

function noop() {}

// The saved copies keep the server's «max-age» header. Handed back as they
// are, the browser would treat them as fresh and reuse them from its own
// memory without asking this worker again, so a reload right after a new
// deploy could still show the old version. Answering with «no-cache» makes
// the browser ask us every time (we still answer from the saved copy when the
// network is missing).
function revalidate(res) {
  if (!res || res.type === 'opaque' || res.status === 0) return res;
  const headers = new Headers(res.headers);
  headers.set('Cache-Control', 'no-cache');
  return new Response(res.body, {
    status: res.status,
    statusText: res.statusText,
    headers: headers,
  });
}
function delay(ms) {
  return new Promise(function (resolve) { setTimeout(function () { resolve(TIMEOUT); }, ms); });
}

self.addEventListener('install', function (event) {
  event.waitUntil((async function () {
    const cache = await caches.open(CACHE);
    const queue = PRECACHE.slice();
    async function worker() {
      while (queue.length) {
        const rel = queue.shift();
        const url = new URL(rel, SCOPE).href;
        try {
          // Already saved: it is refreshed the next time it is used online.
          if (await cache.match(url, { ignoreSearch: true })) continue;
          const res = await fetch(url, { cache: 'reload', credentials: 'same-origin' });
          if (res && res.ok) await cache.put(url, res);
        } catch (_) { /* one missing file must not stop the install */ }
      }
    }
    await Promise.all([worker(), worker(), worker(), worker()]);
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', function (event) {
  event.waitUntil((async function () {
    const keys = await caches.keys();
    // Remove every older cache (including Flutter's legacy ones).
    await Promise.all(keys.filter(function (k) { return k !== CACHE; })
      .map(function (k) { return caches.delete(k); }));
    await self.clients.claim();
  })());
});

async function sameSite(event) {
  const req = event.request;
  const nav = req.mode === 'navigate';
  const cache = await caches.open(CACHE);
  const cached = await cache.match(req.url, { ignoreSearch: true });
  const net = fetch(req.url, { cache: 'no-cache', credentials: 'same-origin' })
    .then(function (res) {
      if (res && res.ok && res.type !== 'opaque') {
        const put = cache.put(req.url, res.clone());
        try { event.waitUntil(put); } catch (_) { put.catch(noop); }
      }
      return res;
    });
  net.catch(noop); // never an unhandled rejection when we answered from the cache
  try {
    const res = cached ? await Promise.race([net, delay(NETWORK_WAIT_MS)]) : await net;
    if (res === TIMEOUT) return revalidate(cached);       // slow network: saved copy now
    if (res.ok || !cached) return revalidate(res);        // fresh answer (or nothing saved)
    if (res.status >= 500) return revalidate(cached);     // server trouble: saved copy
    return revalidate(res);                               // a real 404 etc.
  } catch (_) {
    if (cached) return revalidate(cached);                // offline: saved copy
    if (nav) {
      const home = await cache.match(SCOPE + 'index.html');
      if (home) return revalidate(home);
    }
    return Response.error();
  }
}

async function cdn(event) {
  const cache = await caches.open(CACHE);
  const hit = await cache.match(event.request);
  if (hit) return hit;
  const res = await fetch(event.request);
  if (res && (res.ok || res.type === 'opaque')) {
    const put = cache.put(event.request, res.clone());
    try { event.waitUntil(put); } catch (_) { put.catch(noop); }
  }
  return res;
}

self.addEventListener('fetch', function (event) {
  const req = event.request;
  if (req.method !== 'GET') return;
  let url;
  try { url = new URL(req.url); } catch (_) { return; }
  if (url.origin === self.location.origin) {
    if (url.pathname.indexOf(new URL(SCOPE).pathname) !== 0) return;
    event.respondWith(sameSite(event));
  } else if (CDN_HOSTS.indexOf(url.hostname) >= 0) {
    event.respondWith(cdn(event));
  }
});
