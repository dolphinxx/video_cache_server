# video_cache_server

A Flutter package for caching video data through local proxy server. You can add cache ability to your media player with few codes.

This plugin starts a local `HttpServer`, handles requests with proxied urls, and caches the response data to local disk.

It is designed for media players but can be used for other purposes.

## Getting Started

```dart
VideoCacheServer cacheServer = VideoCacheServer();
await cacheServer.start();
// ...
String url = '...';
String proxyUrl = cacheServer.getProxyUrl(url);
player.setDataSource(proxyUrl);
// ...
cacheServer.stop();
// if you don't persist the cache data, remember to clear the cache.
await cacheServer.clear();
```

## Warning
The cache server can only serve a single request per uri. Subsequent requests with same uri will interrupt the previous one. It is by design to reduce the complex of caching.
