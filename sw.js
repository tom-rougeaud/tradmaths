/* TradMaths — service worker : cache hors ligne versionné.
   Conçu par Tom Rougeaud — rédigé avec l’aide de Claude (Anthropic).
   Ne touche jamais aux appels vers les moteurs de traduction ni vers la base (autres domaines). */
const VERSION='tradmaths-v4-2026-11-18';
const FILES=['./','./index.html','./eleve.html','./manifest.webmanifest','./manifest-eleve.webmanifest','./config.js',
  './vendor/supabase/supabase.js','./vendor/qrcode/qrcode.js','./icon-192.png','./icon-512.png','./apple-touch-icon.png'];
self.addEventListener('install',e=>{e.waitUntil(caches.open(VERSION).then(c=>c.addAll(FILES)))});
self.addEventListener('activate',e=>{
  e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==VERSION).map(k=>caches.delete(k)))).then(()=>self.clients.claim()));
});
self.addEventListener('message',e=>{if(e.data==='skip')self.skipWaiting()});
self.addEventListener('fetch',e=>{
  const r=e.request,u=new URL(r.url);
  if(r.method!=='GET'||u.origin!==location.origin)return;
  /* réseau d'abord (version à jour), cache en secours hors ligne (le « ?c=CODE » de la page élève est ignoré) */
  const page=u.pathname.endsWith('eleve.html')?'./eleve.html':'./index.html';
  e.respondWith(fetch(r).then(res=>{
    if(res&&res.ok&&!u.search){const copy=res.clone();caches.open(VERSION).then(c=>c.put(r,copy))}
    return res;
  }).catch(()=>caches.match(r,{ignoreSearch:true}).then(m=>m||caches.match(page))));
});
