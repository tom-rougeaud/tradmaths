/* TradMaths — service worker : cache hors ligne versionné.
   Ne touche jamais aux appels vers les moteurs de traduction (autres domaines). */
const VERSION='tradmaths-v3b-2026-11-17';
const FILES=['./','./index.html','./manifest.webmanifest','./icon-192.png','./icon-512.png','./apple-touch-icon.png'];
self.addEventListener('install',e=>{e.waitUntil(caches.open(VERSION).then(c=>c.addAll(FILES)))});
self.addEventListener('activate',e=>{
  e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==VERSION).map(k=>caches.delete(k)))).then(()=>self.clients.claim()));
});
self.addEventListener('message',e=>{if(e.data==='skip')self.skipWaiting()});
self.addEventListener('fetch',e=>{
  const r=e.request,u=new URL(r.url);
  if(r.method!=='GET'||u.origin!==location.origin)return;
  /* réseau d'abord (version à jour), cache en secours hors ligne */
  e.respondWith(fetch(r).then(res=>{
    if(res&&res.ok){const copy=res.clone();caches.open(VERSION).then(c=>c.put(r,copy))}
    return res;
  }).catch(()=>caches.match(r).then(m=>m||caches.match('./index.html'))));
});
