// Copyright (c) 2020, dolphinxx <bravedolphinxx@gmail.com>. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import './exception.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:async';

import './m3u8_helper.dart';
import './io_client.dart';
import './io_streamed_response.dart';
import './cache.dart';
import './http_helper.dart';
import 'package:path_provider/path_provider.dart';

/// Return true to pass through the request
typedef PassThrough = FutureOr<bool> Function(ProxyRequest serverRequest, CacheInfo cacheInfo);

/// Return true if the response is finished in this handler.
/// [owner] is the `cacheKey` this uri's cache [belongTo] or owned
typedef PostRemoteRequestHandler = FutureOr Function(Uri uri, IOStreamedResponse remoteResponse, HttpResponse response, VideoCacheServer videoCacheServer, String owner);
typedef BadCertificateCallback = bool Function(X509Certificate cert, String host, int port);

typedef RequestHeaderInterceptor = void Function(Map<String, String> headers);

/// This plugin starts a local [HttpServer], handles requests with particular urls:
///
/// `video_url` => `http://localhost:${proxyServerPort}?url=${Uri.encodeComponent(video_url)}`
///
/// and saves the response data to [cacheDir].
///
/// For m3u8 file requests, the media urls in m3u8 files are replaced by the proxy ones. A living m3u8 is ignored(does not contain a `#EXT-X-ENDLIST`).
/// See [postRemoteRequestHandler] and
///
///
/// See the sample codes for detail usage.

class VideoCacheServer {
  HttpServer _server;

  /// Get the running `HttpServer`
  HttpServer get server => _server;
  final String _address;
  int _port;

  bool quiet = true;

  /// This field is passed to [HttpServer.bind] transparently, see the doc of that method for more information.
  final SecurityContext securityContext;

  /// This field is passed to [HttpServer.bind] transparently, see the doc of that method for more information.
  final int backlog;

  /// This field is passed to [HttpServer.bind] transparently, see the doc of that method for more information.
  final bool shared;
  final bool lazy;

  bool _started = false;

  bool get started => _started;

  /// The [InternetAddress] the cache server is listening on, return null if the server is not started.
  InternetAddress get address => _server?.address;

  /// The port number the cache server is listening on, return null if the server is not started.
  int get port => _server?.port;

  String _cacheDir;

  final BadCertificateCallback badCertificateCallback;

  /// Provide a tester to pass through the request, executed before cache is checked.
  ///
  /// The default one is the [passThroughForMp4TrailingMetadataRequest].
  ///
  /// IjkPlayer performs a metadata request to fetch the trailing few bytes (below 1k), and it interrupts the previous stream request.
  /// Then the player performs a new stream request which may interrupt the previous metadata request, which breaks the seeking functionality.
  /// This doesn't break the caching, since the stream request will walk through the whole data including the passed data range.
  final PassThrough passThrough;

  /// A handler executed immediately after the request to remote returned. The default one is [handleM3u8]
  final PostRemoteRequestHandler postRemoteRequestHandler;

  /// Provide a way to modify the request headers
  RequestHeaderInterceptor requestHeaderInterceptor;

  final Map<String, CacheInfo> _caches = {};

  Map<String, CacheInfo> get caches => /*UnmodifiableMapView(*/ _caches /*)*/;

  /// Queries if any data associated with [url] is cached.
  ///
  /// Returns true if any data from or belong to the [url] is cached, otherwise returns false.
  bool isCached(String url) {
    if (caches.containsKey(url)) {
      return true;
    }
    return _caches.values.any((element) => element.belongTo == url);
  }

  int cacheFileIndex = 0;
  final HttpClient _httpClient;
  http.Client _client;

  /// Instantiate a [VideoCacheServer] that listens on the specified [address] and [port].
  ///
  /// If [address] is not provided, `localhost` will be used.
  ///
  /// A random free port will be picked if [port] is not specified.
  ///
  /// [cacheDir] is the directory for storing cache data, default to `${AppTemporaryDirectory}/video_cache_server/`.
  ///
  /// You can provide a [httpClient] to customize the [HttpClient], and the cache server will set [autoUncompress] to false to let the response consumer do the uncompressing work.
  ///
  /// To prevent unnecessary traffic usage, the cache server responds to the pause/resume signal from the consumer(eg:A media player's buffering strategy).
  /// Set [lazy] to false if you want to cache complete data whenever perform a request regardless of traffic.
  ///
  /// The cache server doesn't provide an in-box persistence functionality since caching multiple video data is usually not necessary.
  ///
  /// You can implement one by yourself if needed. See `local file restoring` test case in unit tests for more information. But you need to manage the lifecycle of the cached data by yourself.
  ///
  /// Provide a tester to [passThrough] particular requests.
  ///
  /// If the [badCertificateCallback] is not provided, a all-pass-through one will be used.
  ///
  /// The [securityContext], [backlog] and [shared] arguments is transparently passed to the [HttpServer.bind], please read doc of that method for more information.
  VideoCacheServer({
    String address,
    int port,
    String cacheDir,
    HttpClient httpClient,
    this.lazy = true,
    this.securityContext,
    this.backlog,
    this.shared,
    this.badCertificateCallback,
    this.passThrough = passThroughForMp4TrailingMetadataRequest,
    this.postRemoteRequestHandler = handleM3u8,
  })  : _address = address ?? 'localhost',
        _port = port,
        _cacheDir = cacheDir,
        _httpClient = httpClient;

  /// Starts the cache server and returns the [VideoCacheServer] instance.
  Future<VideoCacheServer> start() async {
    _cacheDir ??= '${(await getTemporaryDirectory()).path}/video_cache_server/';
    if (!_cacheDir.endsWith('/')) {
      _cacheDir += '/';
    }
    Directory cacheDirectory = Directory(_cacheDir);
    if (cacheDirectory.existsSync() && cacheDirectory.statSync().type != FileSystemEntityType.directory) {
      throw AsyncError('The location which the cacheDir[$_cacheDir] indicates to is not a type of directory!', StackTrace.current);
    }
    cacheDirectory.createSync(recursive: true);
    _server = await _serve(_address, _port ?? 0, securityContext: securityContext);
    _port = _server.port;
    _started = true;
    if (quiet != true) {
      print('Video Cache Server serving at http${securityContext == null ? "" : "s"}://${_server.address.host}:${_server.port}');
    }
    return this;
  }

  /// Stops the cache server.
  void stop() {
    try {
      _server?.close(force: true);
    } catch (e, s) {
      print('failed to close cache proxy HttpServer.\n$e\n$s');
    }
    _started = false;
  }

  /// Clears the held cache info and the cache files.
  Future<void> clear() async {
    _caches.clear();
    cacheFileIndex = 0;
    if(_cacheDir != null) {
      Directory cacheDir = Directory(_cacheDir);
      if (cacheDir.existsSync()) {
        for (FileSystemEntity file in cacheDir.listSync()) {
          try {
            file.deleteSync(recursive: true);
          } catch (e) {
            print(e);
          }
        }
      }
    }
  }

  /// Starts an [HttpServer] that listens on the specified [address] and
  /// [port] and sends requests to [_proxyAndCache].
  Future<HttpServer> _serve(address, int port, {SecurityContext securityContext, int backlog, bool shared = false}) async {
    backlog ??= 0;
    HttpServer server = await (securityContext == null
        ? HttpServer.bind(address, port, backlog: backlog, shared: shared)
        : HttpServer.bindSecure(address, port, securityContext, backlog: backlog, shared: shared));
    _client ??= IOClient((_httpClient ?? HttpClient())
      ..autoUncompress = false
      ..badCertificateCallback = badCertificateCallback ?? (X509Certificate cert, String host, int port) => true);
    var onError = (e, s) {
      print('Proxy Server stopped with asynchronous error\n$e\n$s');
      try {
        _client.close();
      } catch (_) {}
    };
    var callback = () {
      server.listen((HttpRequest request) => handleRequest(request), onDone: () {
        try {
          _client.close();
        } catch (_) {}
      }, onError: onError);
    };
    if (Zone.current.inSameErrorZone(Zone.root)) {
      runZonedGuarded(callback, onError);
    } else {
      callback();
    }
    return server;
  }

  Future<void> handleRequest(HttpRequest request) async {
    ProxyRequest shelfRequest;
    shelfRequest = ProxyRequest.fromHttpRequest(request);
    try {
      await _proxyAndCache(shelfRequest, request.response);
    } catch (error, stackTrace) {
      print('Error occurred while handling request by proxy server.\n$error\n$stackTrace');
      HttpResponse httpResponse = request.response;
      try {
        httpResponse.statusCode = 500;
        await httpResponse.flush();
        await httpResponse.close();
      } catch (_) {}
    }
  }

  /// Gets a proxy url for [raw] which will be handled by the cache server.
  ///
  /// [extraQueries] will be appended to the generated url, note that query key starts and ends with `__` is preserved to carry metadata and will not be appended to the actual video url.
  String getProxyUrl(String raw, [Map<String, String> extraQueries]) {
    String _extraQueries;
    if(extraQueries?.isNotEmpty == true) {
      _extraQueries = '&' + extraQueries.keys.map((key) => '$key=${Uri.encodeComponent(extraQueries[key])}').join('&');
    }
    return 'http${securityContext == null ? "" : "s"}://${address.host}:$port/?__url__=${Uri.encodeComponent(raw)}${_extraQueries??""}';
  }

  /// Pass through the request for fetching mp4 metadata, this is usually happened when the player detected that the metadata is at the end of the mp4 file.
  static bool passThroughForMp4TrailingMetadataRequest(ProxyRequest serverRequest, CacheInfo cacheInfo) {
    RequestRange requestRange = RequestRange.parse(serverRequest.headers['range']);
    if (cacheInfo != null &&
        requestRange.specified &&
        (requestRange.end != null || cacheInfo.total != null) &&
        requestRange.begin != null &&
        ((requestRange.end ?? cacheInfo.total) - requestRange.begin < 1024 && !cacheInfo.cached(requestRange))) {
      print('request passed through');
      return true;
    }
    return false;
  }

  /// Intercept and proxy m3u8 content.
  static Future<bool> handleM3u8(Uri uri, IOStreamedResponse remoteResponse, HttpResponse response, VideoCacheServer server, String owner) async {
    if (isM3u8(remoteResponse.headers['content-type']?.toLowerCase(), uri)) {
      // For a m3u8 request, download and change the URIs in it to proxied version
      String m3u8;
      if (remoteResponse.headers['content-encoding'] == 'gzip') {
        response.headers.remove('content-encoding', 'gzip');
        m3u8 = await http.ByteStream(remoteResponse.stream.cast<List<int>>().transform(gzip.decoder)).bytesToString();
      } else {
        m3u8 = await remoteResponse.stream.bytesToString();
      }
      Map<String, String> ownerQuery = owner == null ? null : {'__owner__': owner};
      M3u8 _m3u8 = proxyM3u8Content(m3u8, (url) => server.getProxyUrl(url, ownerQuery), remoteResponse.requestUri);

      // print('-- M3U8:\n${_m3u8.proxied}');
      List<int> bytes = utf8.encode(_m3u8.proxied);
      response.contentLength = bytes.length;
      if (remoteResponse.statusCode == 206) {
        response.headers.set('content-range', 'bytes 0-${bytes.length - 1}/${bytes.length}');
      }
      response.add(bytes);
      await response.flush();
      await response.close();
      return true;
    }
    return false;
  }

  /// The actual codes of doing proxy and caching work.
  Future<void> _proxyAndCache(ProxyRequest serverRequest, HttpResponse response) async {
    String realUrl;
    String cacheKey;
    String owner;
    List<String> extraParams = [];
    serverRequest.requestedUri.queryParameters.forEach((key, value) {
      if(key == '__url__') {
        realUrl = value;
        return;
      }
      if(key == '__key__') {
        cacheKey = key;
        return;
      }
      if(key == '__owner__') {
        owner = value;
        return;
      }
      if(key.startsWith('__') && key.endsWith('__')) {
        return;
      }
      extraParams.add('$key=${Uri.encodeComponent(value)}');
    });
    cacheKey ??= realUrl;
    if(extraParams.isNotEmpty) {// ie: m3u8 encrypt queries
      realUrl = appendQuery(realUrl, extraParams.join('&'));
    }

    CacheInfo cacheInfo = _caches[cacheKey];
    if (passThrough != null && await passThrough(serverRequest, cacheInfo)) {
      await _passThrough(realUrl, serverRequest, response);
      return;
    }

    RequestRange requestRange = RequestRange.parse(serverRequest.headers['range']);
    if (quiet != true) {
      print('VideoCacheServer handling [begin:${requestRange.begin ?? 0}, end:${requestRange.end ?? ""}, url:$realUrl]');
    }

    if (cacheInfo != null && (cacheInfo.cached(requestRange))) {
      // cache exists and finished download, don't perform another request
      if (cacheInfo.headers != null) {
        cacheInfo.headers.forEach((key, value) => response.headers.set(key, value));
      }

      if (requestRange.specified) {
        response.statusCode = 206;
        if (requestRange.begin == null) {
          requestRange.suffixLengthToRange(cacheInfo.total);
        }
        if (requestRange.begin == 0) {
          if (requestRange.end == null) {
            response.contentLength = cacheInfo.total;
          } else {
            response.contentLength = requestRange.end + 1;
          }
        } else {
          if (requestRange.end == null) {
            response.contentLength = cacheInfo.total - requestRange.begin;
          } else {
            response.contentLength = requestRange.end - requestRange.begin + 1;
          }
        }
        response.headers.set('content-range', 'bytes ${requestRange.begin}-${requestRange.begin + response.contentLength - 1}/${cacheInfo.total}');
        await response.addStream(cacheInfo.streamFromCache(
          begin: requestRange.begin,
          end: requestRange.end == null ? cacheInfo.total : requestRange.end + 1,
        ));
      } else {
        response.statusCode = 200;
        response.contentLength = cacheInfo.total;
        response.headers.removeAll('content-range');
        await response.addStream(cacheInfo.streamFromCache(begin: 0, end: cacheInfo.total));
      }
      await response.flush();
      try {
        await response.close();
      } catch (e, s) {
        if (e is HttpException && e.message.contains('Content size below specified contentLength. ')) {
          return;
        }
        print('failed to close response.$e\n$s');
        throw AsyncError(e, s);
      }
      if (quiet != true) {
        print('Request finished from cache - [${requestRange.begin ?? 0}-${requestRange.end}, url:$realUrl]');
      }
      return;
    }

    if (cacheInfo == null) {
      cacheInfo = CacheInfo(url: realUrl, lazy: lazy, belongTo: owner)..current = 0;
      _caches[cacheKey] = cacheInfo;
    }
    IOStreamedResponse clientResponse;
    try {
      Uri realUri = Uri.parse(realUrl);
      http.Request clientRequest = http.Request(serverRequest.method, realUri);
      clientRequest.followRedirects = true;
      clientRequest.headers.addAll(serverRequest.headers);
      String host = realUri.host;
      if(!(realUri.port == 80 && realUri.scheme == 'http' || realUri.port == 443 && realUri.scheme == 'https')) {
        host = '$host:${realUri.port}';
      }
      clientRequest.headers['host'] = host;

      if(requestHeaderInterceptor != null) {
        requestHeaderInterceptor(clientRequest.headers);
      }

      List<int> bodyBytes = [];
      await serverRequest.read().forEach((element) => bodyBytes.addAll(element));
      clientRequest.bodyBytes = bodyBytes;

      clientResponse = await _client.send(clientRequest);
      // print('====== Proxy Response[${requestRange.begin??0}-${requestRange.end}] ======');
      // print('StatusCode:${clientResponse.statusCode}');
      clientResponse.headers.forEach((key, value) {
        if (value == null) return;
        response.headers.set(key, value);
        // print('Header:$key=$value');
      });
      // print('============================');
      if (clientResponse.statusCode < 200 || clientResponse.statusCode >= 300) {
        // response data invalid
        response.statusCode = clientResponse.statusCode;
        response.contentLength = clientResponse.contentLength ?? -1;
        clientResponse.headers.forEach((key, value) {
          if (value == null) return;
          response.headers.set(key, value);
        });
        await response.addStream(clientResponse.stream);
        await response.close();
        return;
      }

      cacheInfo.headers ??= Map.from(clientResponse.headers);
      ResponseRange responseRange =
          clientResponse.statusCode == 206 ? ResponseRange.parse(clientResponse.headers['content-range']) : ResponseRange.unspecified();
      if (cacheInfo.total == null) {
        if (responseRange.specified) {
          cacheInfo.total = responseRange.size;
        } else {
          cacheInfo.total = clientResponse.contentLength;
        }
      }

      response.statusCode = clientResponse.statusCode;
      response.contentLength = clientResponse.contentLength ?? -1;

      if (postRemoteRequestHandler != null && await postRemoteRequestHandler(realUri, clientResponse, response, this, owner??cacheKey)) {
        // don't hold cache info
        _caches.remove(cacheKey);
        return;
      }

      int begin = requestRange.specified ? requestRange.begin : 0;
      await response.addStream(await cacheInfo.stream(
        begin: begin,
        end: requestRange.specified ? (requestRange.end == null ? cacheInfo.total : requestRange.end + 1) : cacheInfo.total,
        createFragmentFile: () => File('$_cacheDir${cacheFileIndex++}'),
        clientResponse: (!responseRange.specified || (responseRange.begin != null && responseRange.begin <= begin)) ? clientResponse : null,
        client: _client,
        clientRequest: clientRequest,
      ));
      await response.flush();
      if (quiet != true) {
        print('Request finished - [${requestRange.begin ?? 0}-${requestRange.end}, url:$realUrl]');
      }
      try {
        await response.close();
      } catch (e, s) {
        if (e is HttpException && e.message.contains('Content size below specified contentLength. ')) {
          // print('Warn:[${requestRange.begin??0}-${requestRange.end??""}]Content size below specified contentLength.');
          return;
        }
        print('failed to close response.$e\n$s');
        // throw AsyncError(e, s);
      }
    } catch (e, s) {
      if (e is! InterruptedError) {
        print('error occurred while proxying $realUrl.$e\n$s');
      }
      if (clientResponse == null) {
        // remote request failed, write the error to response
        response.contentLength = 0;
        response.statusCode = 500;
        response.reasonPhrase = e.toString();
      }
      try {
        await response.close();
      } catch (_) {}
    }
  }

  Future<void> _passThrough(String realUrl, ProxyRequest serverRequest, HttpResponse response) async {
    Uri realUri = Uri.parse(realUrl);
    http.Request clientRequest = http.Request(serverRequest.method, realUri);
    clientRequest.followRedirects = true;
    clientRequest.headers.addAll(serverRequest.headers);
    clientRequest.headers['host'] = realUri.host;
    IOStreamedResponse clientResponse = await _client.send(clientRequest);
    response.statusCode = clientResponse.statusCode;
    response.contentLength = clientResponse.contentLength ?? -1;
    clientResponse.headers.forEach((key, value) {
      if (value == null) return;
      response.headers.set(key, value);
    });
    await response.addStream(clientResponse.stream);
    await response.close();
  }
}
