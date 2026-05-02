const CACHE_NAME = 'family-cookbook-shell-v1'
const APP_SHELL = ['/', '/manifest.webmanifest', '/apple-touch-icon.svg', '/pwa-icon.svg']
const PENDING_SYNC_TAG = 'family-cookbook-pending-sync'

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(APP_SHELL)
    }),
  )
  self.skipWaiting()
})

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys
          .filter((key) => key !== CACHE_NAME)
          .map((key) => caches.delete(key)),
      ),
    ),
  )
  self.clients.claim()
})

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') {
    return
  }

  const requestUrl = new URL(event.request.url)
  if (requestUrl.origin !== self.location.origin) {
    return
  }

  event.respondWith(
    fetch(event.request)
      .then((response) => {
        const responseClone = response.clone()
        caches.open(CACHE_NAME).then((cache) => {
          cache.put(event.request, responseClone)
        })
        return response
      })
      .catch(() => caches.match(event.request).then((cached) => cached || caches.match('/'))),
  )
})

self.addEventListener('message', (event) => {
  if (event.data?.type === 'SKIP_WAITING') {
    self.skipWaiting()
    return
  }

  if (event.data?.type === 'PENDING_COOKBOOK_CHANGED') {
    event.waitUntil(notifyClients('pending-change'))
  }
})

self.addEventListener('sync', (event) => {
  if (event.tag === PENDING_SYNC_TAG) {
    event.waitUntil(notifyClients('background-sync'))
  }
})

self.addEventListener('periodicsync', (event) => {
  if (event.tag === PENDING_SYNC_TAG) {
    event.waitUntil(notifyClients('periodic-sync'))
  }
})

async function notifyClients(source) {
  const clients = await self.clients.matchAll({ type: 'window', includeUncontrolled: true })
  await Promise.all(
    clients.map((client) =>
      client.postMessage({
        type: 'SYNC_PENDING_COOKBOOK',
        source,
      }),
    ),
  )
}
