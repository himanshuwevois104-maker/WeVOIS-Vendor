/* Network-first service worker.
   Network-first, not cache-first, on purpose: a settlement figure that is one
   deploy out of date is worse than a page that takes an extra moment to load.
   Bump CACHE_VERSION on every deploy so installed phones pick the new build up. */

var CACHE_VERSION = "vs-v1";
var SHELL = ["./index.html","./styles.css","./vs-core.js","./vs-views.js","./vs-actions.js",
             "./supabase-config.js","./manifest.json"];

self.addEventListener("install", function(e){
  self.skipWaiting();
  e.waitUntil(caches.open(CACHE_VERSION).then(function(c){ return c.addAll(SHELL).catch(function(){}); }));
});

self.addEventListener("activate", function(e){
  e.waitUntil(
    caches.keys().then(function(keys){
      return Promise.all(keys.filter(function(k){ return k !== CACHE_VERSION; })
                            .map(function(k){ return caches.delete(k); }));
    }).then(function(){ return self.clients.claim(); })
  );
});

self.addEventListener("fetch", function(e){
  var url = e.request.url;
  /* never cache anything that talks to the database */
  if(url.indexOf("supabase.co") >= 0 || url.indexOf("/rest/v1") >= 0 ||
     url.indexOf("/auth/v1") >= 0 || e.request.method !== "GET") return;

  e.respondWith(
    fetch(e.request).then(function(res){
      var copy = res.clone();
      caches.open(CACHE_VERSION).then(function(c){ c.put(e.request, copy).catch(function(){}); });
      return res;
    }).catch(function(){
      return caches.match(e.request).then(function(hit){
        return hit || caches.match("./index.html");
      });
    })
  );
});
