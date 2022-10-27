import 'dart:async';
import 'dart:typed_data';

import 'dart:developer' show log;

import 'package:flutter_test/flutter_test.dart';

import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

import 'package:video_cache_server/video_cache_server.dart';
import './file_server.dart';


void main() {
  // A random selected file for testing purpose only.
  String testFileUrl = 'https://mirror.bit.edu.cn/apache/hadoop/core/hadoop-3.3.0/hadoop-3.3.0-aarch64.tar.gz';
  String testFilePath = '/tmp/test/hadoop-3.3.0-aarch64.tar.gz';
  int testFileSize = 501375126;
  String testFileChecksum = '560957867016591759EB73DA39E673AE3902EE1C3AED912FD421478AD4E4146F';
  String cacheDir = '/tmp/test/video_proxy_cache';
  math.Random random = math.Random();
  randomPosition(int length) => math.min((random.nextDouble() * length).toInt(), length - 1);
  Future<String> calcChecksum(Stream<List<int>> stream) async {
    return (await sha256.bind(stream).first).toString();
  }

  Future<List<int>> readFileInRange(String file, int begin, int end) async {
    return File(file).openRead(begin, end).fold<List<int>>(<int>[], (List<int> previous, List<int> element) => previous..addAll(element));
  }

  int requestId = 1;
  Future<Uint8List?> performRequest(int begin, int? end, String proxyUrl, int expectedLength) async {
    int id = requestId++;
    log('request $id started...');
    try {
      http.Request request = http.Request('GET', Uri.parse(proxyUrl));
      if (begin > 0 || (end != null && end < expectedLength)) {
        request.headers['range'] = 'bytes=$begin-${end != null ? end - 1 : ""}';
      }
      http.StreamedResponse response = await http.Client().send(request);
      return await response.stream.toBytes();
    } catch (e) {
      log('Request Error:$e');
      return null;
    } finally {
      log('request $id finished.');
    }
  }
  int sum(List<int>? list) {
    if(list == null) {
      return -1;
    }
    return list.reduce((value, element) => value + element);
  }

  test('local file single request', () async {
    late HttpServer server;
    late VideoCacheServer videoCacheServer;
    try {
      int expectedLength = testFileSize;
      String expectedChecksum = testFileChecksum;
      videoCacheServer = VideoCacheServer(cacheDir: cacheDir);
      await videoCacheServer.start();

      server = await serve(testFilePath);
      String url = 'http://127.0.0.1:${server.port}';
      String proxyUrl = videoCacheServer.getProxyUrl(url);
      http.Request request = http.Request('GET', Uri.parse(proxyUrl));
      request.headers['Connection']='close';
      request.headers['User-Agent'] = 'Mozilla/5.0 (iPhone; CPU iPhone OS 11_0 like Mac OS X) AppleWebKit/604.1.38 (KHTML, like Gecko) Version/11.0 Mobile/15A372 Safari/604.1';
      request.headers['Accept'] = '*/*';
      request.headers['Icy-MetaData'] = '1';

      http.StreamedResponse response = await http.Client().send(request);
      int received = 0;
      String checksum = await calcChecksum(response.stream.where((event) {
        // print('calc:${event.length}');
        received += event.length;
        return true;
      }));
      await server.close();
      CacheInfo cache = videoCacheServer.caches[url]!;

      log('Cache:');
      cache.fragments.sort((a, b) => a.begin - b.begin);
      for (int i = 0; i < cache.fragments.length; i++) {
        CacheFragment fragment = cache.fragments[i];
        log('fragment ${i + 1}:${fragment.expected} => ${fragment.begin}-${fragment.end}=${fragment.received}');
      }
      expect(received, expectedLength, reason: 'length should be same');
      expect(checksum.toLowerCase(), expectedChecksum.toLowerCase(), reason: 'checksum should be same.');

      // Request after the file server closed, the cache will do the magic
      log('New request...');
      request = http.Request('GET', Uri.parse(proxyUrl));
      response = await http.Client().send(request);
      received = 0;
      checksum = await calcChecksum(response.stream.where((event) {
        received += event.length;
        return true;
      }));
      cache.fragments.sort((a, b) => a.begin - b.begin);
      int cachedSize = 0;
      for (int i = 0; i < cache.fragments.length; i++) {
        CacheFragment fragment = cache.fragments[i];
        cachedSize += fragment.received;
        log('fragment ${i + 1}:${fragment.expected} => ${fragment.begin}-${fragment.end}=${fragment.received}');
      }
      expect(cachedSize, expectedLength, reason: 'cached data size should be equal to expected');

      expect(checksum.toLowerCase(), expectedChecksum.toLowerCase(), reason: 'checksum should be same.');
      expect(received, expectedLength, reason: 'length should be same');
    } finally {
      videoCacheServer.stop();
      unawaited(videoCacheServer.clear());
    }
  }, timeout: const Timeout(Duration(days: 1)));
  test('remote file single request', () async {
    late VideoCacheServer videoCacheServer;
    try {
      int expectedLength = testFileSize;
      String expectedChecksum = testFileChecksum;
      videoCacheServer = VideoCacheServer(cacheDir: cacheDir);
      await videoCacheServer.start();

      String proxyUrl = videoCacheServer.getProxyUrl(testFileUrl);
      http.Request request = http.Request('GET', Uri.parse(proxyUrl));
      // request.headers['Connection']='Keep-Alive';
      http.StreamedResponse response = await http.Client().send(request);
      int received = 0;
      String checksum = await calcChecksum(response.stream.where((event) {
        // print('calc:${event.length}');
        received += event.length;
        return true;
      }));
      CacheInfo cache = videoCacheServer.caches[testFileUrl]!;

      log('Cache:');
      cache.fragments.sort((a, b) => a.begin - b.begin);
      for (int i = 0; i < cache.fragments.length; i++) {
        CacheFragment fragment = cache.fragments[i];
        log('fragment ${i + 1}:${fragment.expected} => ${fragment.begin}-${fragment.end}=${fragment.received}');
      }
      expect(received, expectedLength, reason: 'length should be same');
      expect(checksum.toLowerCase(), expectedChecksum.toLowerCase(), reason: 'checksum should be same.');

      // The cache will serve data.
      log('Offline request...');
      int start = DateTime.now().millisecondsSinceEpoch;
      request = http.Request('GET', Uri.parse(proxyUrl));
      response = await http.Client().send(request);
      received = 0;
      checksum = await calcChecksum(response.stream.where((event) {
        received += event.length;
        return true;
      }));
      cache.fragments.sort((a, b) => a.begin - b.begin);
      int cachedSize = 0;
      for (int i = 0; i < cache.fragments.length; i++) {
        CacheFragment fragment = cache.fragments[i];
        cachedSize += fragment.received;
        log('fragment ${i + 1}:${fragment.expected} => ${fragment.begin}-${fragment.end}=${fragment.received}');
      }
      expect(cachedSize, expectedLength, reason: 'cached data size should be equal to expected');

      log('Second request coast:${DateTime.now().millisecondsSinceEpoch - start}ms');
      expect(checksum.toLowerCase(), expectedChecksum.toLowerCase(), reason: 'checksum should be same.');
      expect(received, expectedLength, reason: 'length should be same');
    } finally {
      videoCacheServer.stop();
      unawaited(videoCacheServer.clear());
    }
  }, timeout: const Timeout(Duration(days: 1)), skip: true);
  test('local file multiple request', () async {
    late HttpServer server;
    late VideoCacheServer videoCacheServer;
    try {
      int expectedLength = testFileSize;
      String expectedChecksum = testFileChecksum;
      videoCacheServer = VideoCacheServer(cacheDir: cacheDir);
      await videoCacheServer.start();

      server = await serve(testFilePath);
      String url = 'http://127.0.0.1:${server.port}';
      String proxyUrl = videoCacheServer.getProxyUrl(url);

      int received = 0;
      performRequest(int begin, int end, String proxyUrl, int expectedLength) async {
        http.Request request = http.Request('GET', Uri.parse(proxyUrl));
        request.headers['range'] = 'bytes=$begin-${end - 1}';
        http.StreamedResponse response = await http.Client().send(request);
        received += (await response.stream.toBytes()).length;
      }
      await performRequest(501371111, 501375126, proxyUrl, expectedLength);
      await performRequest(0, 125343781, proxyUrl, expectedLength);
      await performRequest(125343781, 250687563, proxyUrl, expectedLength);
      await performRequest(250687563, 501371111, proxyUrl, expectedLength);
      unawaited(server.close());

      CacheInfo cache = videoCacheServer.caches[url]!;
      log('Cache:');
      cache.fragments.sort((a, b) => a.begin - b.begin);
      int cachedSize = 0;
      for (int i = 0; i < cache.fragments.length; i++) {
        CacheFragment fragment = cache.fragments[i];
        cachedSize += fragment.received;
        log('fragment ${i + 1}:${fragment.expected} => ${fragment.begin}-${fragment.end}=${fragment.received}');
      }
      expect(cachedSize, expectedLength, reason: 'cached data size should be equal to expected');
      expect(received, expectedLength, reason: 'length should be same');

      // Request after the file server closed, the cache will serve data
      log('Offline request...');
      http.Request request = http.Request('GET', Uri.parse(proxyUrl));
      http.StreamedResponse response = await http.Client().send(request);
      String checksum = await calcChecksum(response.stream.where((event) {
        return true;
      }));
      expect(checksum.toLowerCase(), expectedChecksum.toLowerCase(), reason: 'checksum should be same.');
    } finally {
      videoCacheServer.stop();
      unawaited(videoCacheServer.clear());
    }
  }, timeout: const Timeout(Duration(days: 1)));
  test('local file simulate seeking', () async {
    late HttpServer server;
    late VideoCacheServer videoCacheServer;
    try {
      int expectedLength = testFileSize;
      String expectedChecksum = testFileChecksum;
      videoCacheServer = VideoCacheServer(cacheDir: cacheDir, httpClient: HttpClient()..connectionTimeout = const Duration(seconds: 5));
      await videoCacheServer.start();

      server = await serve(testFilePath);
      String url = 'http://127.0.0.1:${server.port}';
      String proxyUrl = videoCacheServer.getProxyUrl(url);

      int received = 0;

      unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
      await Future.delayed(const Duration(milliseconds: 2000));
      unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
      await Future.delayed(const Duration(milliseconds: 500));
      unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
      await Future.delayed(const Duration(milliseconds: 200));
      unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
      await Future.delayed(const Duration(milliseconds: 200));
      unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
      await Future.delayed(const Duration(milliseconds: 300));
      unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
      await Future.delayed(const Duration(milliseconds: 200));
      unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
      await Future.delayed(const Duration(milliseconds: 200));
      unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
      await Future.delayed(const Duration(milliseconds: 500));
      unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
      await Future.delayed(const Duration(milliseconds: 200));
      unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
      await Future.delayed(const Duration(milliseconds: 1000));
      unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
      await Future.delayed(const Duration(milliseconds: 200));
      unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
      await Future.delayed(const Duration(milliseconds: 2000));
      unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
      await Future.delayed(const Duration(milliseconds: 200));
      unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
      await Future.delayed(const Duration(milliseconds: 1000));
      unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
      await Future.delayed(const Duration(milliseconds: 3000));
      unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
      await Future.delayed(const Duration(milliseconds: 2000));
      await performRequest((expectedLength * 3) ~/ 4, null, proxyUrl, expectedLength).then((value) => expect(sum(value!), greaterThan(0)));
      await Future.delayed(const Duration(milliseconds: 2000));
      // a full request to ensure that all data is cached.
      await performRequest(0, null, proxyUrl, expectedLength);
      await server.close().then((_) => log('File Server closes!'));

      CacheInfo cache = videoCacheServer.caches[url]!;
      log('Cache:');
      cache.fragments.sort((a, b) => a.begin - b.begin);
      int cachedSize = 0;
      for (int i = 0; i < cache.fragments.length; i++) {
        CacheFragment fragment = cache.fragments[i];
        cachedSize += fragment.received;
        log('fragment ${i + 1}:${fragment.expected} => ${fragment.begin}-${fragment.end}=${fragment.received}');
      }
      expect(cachedSize, expectedLength, reason: 'cached data size should be equal to expected');

      // Request after the file server closed, the cache will serve data
      log('Offline request...');
      expect((await performRequest(100, 1124, proxyUrl, expectedLength))!.length, 1024, reason: 'A seeking request should return correct data after file server closed.');
      expect((await performRequest(0, 100, proxyUrl, expectedLength))!.length, 100, reason: 'A seeking request should return correct data after file server closed.');
      expect((await performRequest(4096, null, proxyUrl, expectedLength))!.length, expectedLength - 4096, reason: 'A seeking request should return correct data after file server closed.');
      http.Request request = http.Request('GET', Uri.parse(proxyUrl));
      http.StreamedResponse response = await http.Client().send(request);
      String checksum = await calcChecksum(response.stream.where((event) {
        received += event.length;
        return true;
      }));
      expect(received, expectedLength, reason: 'received data size should be equal to expected');
      expect(checksum.toLowerCase(), expectedChecksum.toLowerCase(), reason: 'checksum should be same.');
    } finally {
      videoCacheServer.stop();
      unawaited(videoCacheServer.clear());
    }
  }, timeout: const Timeout(Duration(days: 1)));
  test(
    'trailingBypassThreshold caught',
    () async {
      late HttpServer server;
      late VideoCacheServer videoCacheServer;
      try {
        int expectedLength = testFileSize;
        videoCacheServer = VideoCacheServer(cacheDir: cacheDir, httpClient: HttpClient()..connectionTimeout = const Duration(seconds: 5));
        await videoCacheServer.start();

        server = await serve(testFilePath);
        String url = 'http://127.0.0.1:${server.port}';
        String proxyUrl = videoCacheServer.getProxyUrl(url);

        unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
        await Future.delayed(const Duration(milliseconds: 2000));
        // a request with range refer to trailing few bytes.
        unawaited(performRequest(expectedLength - 1000, expectedLength, proxyUrl, expectedLength).then((v) => expect(v!.length, 1000, reason: 'this request should not be interrupted.')));
        await Future.delayed(const Duration(milliseconds: 500));
        unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
        await Future.delayed(const Duration(milliseconds: 500));
        unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
        await Future.delayed(const Duration(milliseconds: 500));
        unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
        await Future.delayed(const Duration(milliseconds: 500));
        unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
        await Future.delayed(const Duration(milliseconds: 500));
        unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
        await Future.delayed(const Duration(milliseconds: 500));
        unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
        await Future.delayed(const Duration(milliseconds: 500));
        unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
        await Future.delayed(const Duration(milliseconds: 2000));
        unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
        await Future.delayed(const Duration(milliseconds: 2000));
        unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
        await Future.delayed(const Duration(milliseconds: 2000));
        await performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength)
            .then((value) => expect(sum(value!), greaterThan(0), reason: 'awaited request should not be interrupted.'));
        await Future.delayed(const Duration(milliseconds: 2000));
        // a full request to ensure that all data is cached.
        await performRequest(0, null, proxyUrl, expectedLength);
        await server.close().then((_) => log('File Server closes!'));

        CacheInfo cache = videoCacheServer.caches[url]!;
        log('Cache:');
        cache.fragments.sort((a, b) => a.begin - b.begin);
        int cachedSize = 0;
        for (int i = 0; i < cache.fragments.length; i++) {
          CacheFragment fragment = cache.fragments[i];
          cachedSize += fragment.received;
          log('fragment ${i + 1}:${fragment.expected} => ${fragment.begin}-${fragment.end}=${fragment.received}');
        }
        expect(cachedSize, expectedLength, reason: 'cached data size should be equal to expected');
      } finally {
        videoCacheServer.stop();
        unawaited(videoCacheServer.clear());
      }
    },
    timeout: const Timeout(Duration(days: 1)),
  );
  test(
    'trailingBypassThreshold missed',
    () async {
      late HttpServer server;
      late VideoCacheServer videoCacheServer;
      try {
        int expectedLength = testFileSize;
        videoCacheServer = VideoCacheServer(cacheDir: cacheDir, httpClient: HttpClient()..connectionTimeout = const Duration(seconds: 5));
        await videoCacheServer.start();

        server = await serve(testFilePath);
        String url = 'http://127.0.0.1:${server.port}';
        String proxyUrl = videoCacheServer.getProxyUrl(url);

        unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
        await Future.delayed(const Duration(milliseconds: 2000));
        unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
        await Future.delayed(const Duration(milliseconds: 2000));
        // a request with range refer to trailing few bytes.
        unawaited(performRequest(expectedLength - 1000, expectedLength, proxyUrl, expectedLength));
        await Future.delayed(const Duration(milliseconds: 500));
        unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
        await Future.delayed(const Duration(milliseconds: 100));
        unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
        await Future.delayed(const Duration(milliseconds: 100));
        unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
        await Future.delayed(const Duration(milliseconds: 3000));
        await performRequest(376031344, null, proxyUrl, expectedLength).then((value) => expect(value!.length, greaterThan(0), reason: 'awaited request should not be interrupted.'));
        await Future.delayed(const Duration(milliseconds: 5000));
        // a full request to ensure that all data is cached.
        await performRequest(0, null, proxyUrl, expectedLength);
        await server.close().then((_) => log('File Server closes!'));

        CacheInfo cache = videoCacheServer.caches[url]!;
        log('Cache:');
        cache.fragments.sort((a, b) => a.begin - b.begin);
        int cachedSize = 0;
        for (int i = 0; i < cache.fragments.length; i++) {
          CacheFragment fragment = cache.fragments[i];
          cachedSize += fragment.received;
          log('fragment ${i + 1}:${fragment.expected} => ${fragment.begin}-${fragment.end}=${fragment.received}');
        }
        expect(cachedSize, expectedLength, reason: 'cached data size should be equal to expected');
      } finally {
        videoCacheServer.stop();
        unawaited(videoCacheServer.clear());
      }
    },
    timeout: const Timeout(Duration(days: 1)), /* skip: 'Test might fail if the requests do not performed in order.'*/
  );
  test('local file restoring', () async {
    late HttpServer server;
    late VideoCacheServer videoCacheServer;
    try {
      int expectedLength = testFileSize;
      String expectedChecksum = testFileChecksum;
      videoCacheServer = VideoCacheServer(cacheDir: cacheDir, httpClient: HttpClient()..connectionTimeout = const Duration(seconds: 5));
      await videoCacheServer.start();

      server = await serve(testFilePath);
      String url = 'http://127.0.0.1:${server.port}';
      String proxyUrl = videoCacheServer.getProxyUrl(url);

      int received = 0;

      unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
      await Future.delayed(const Duration(milliseconds: 2000));
      unawaited(performRequest(expectedLength - 1000, expectedLength, proxyUrl, expectedLength));
      await Future.delayed(const Duration(milliseconds: 500));
      unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
      await Future.delayed(const Duration(milliseconds: 2000));
      unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
      await Future.delayed(const Duration(milliseconds: 2000));
      unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
      await Future.delayed(const Duration(milliseconds: 2000));
      unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
      await Future.delayed(const Duration(milliseconds: 2000));
      unawaited(performRequest(randomPosition(expectedLength), null, proxyUrl, expectedLength));
      await Future.delayed(const Duration(milliseconds: 2000));
      // a full request to ensure that all data is cached.
      await performRequest(0, null, proxyUrl, expectedLength);
      await server.close().then((_) => log('File Server closes!'));

      CacheInfo cache = videoCacheServer.caches[url]!;
      log('Cache:');
      cache.fragments.sort((a, b) => a.begin - b.begin);
      int cachedSize = 0;
      for (int i = 0; i < cache.fragments.length; i++) {
        CacheFragment fragment = cache.fragments[i];
        cachedSize += fragment.received;
        log('fragment ${i + 1}:${fragment.expected} => ${fragment.begin}-${fragment.end}=${fragment.received}');
      }
      expect(cachedSize, expectedLength, reason: 'cached data size should be equal to expected');

      videoCacheServer.stop();
      String cacheDataStr = jsonEncode(videoCacheServer.caches);
      // instantiate a new cache server.
      videoCacheServer = VideoCacheServer(cacheDir: cacheDir);
      // restore the cache data.
      Map cacheData = jsonDecode(cacheDataStr) as Map;
      cacheData.forEach((key, value) => videoCacheServer.caches[key as String] = CacheInfo.fromMap(value as Map));
      await videoCacheServer.start();

      // now we perform a request but forgot to start the file server.
      log('New request...');
      http.Request request = http.Request('GET', Uri.parse(videoCacheServer.getProxyUrl(url)));
      http.StreamedResponse response = await http.Client().send(request);
      String checksum = await calcChecksum(response.stream.where((event) {
        received += event.length;
        return true;
      }));
      expect(received, expectedLength, reason: 'received data size should be equal to expected');
      expect(checksum.toLowerCase(), expectedChecksum.toLowerCase(), reason: 'checksum should be same.');
    } finally {
      videoCacheServer.stop();
      unawaited(videoCacheServer.clear());
    }
  }, timeout: const Timeout(Duration(days: 1)));
  test('test range contained in the cache in middle', () async {
    //
    // cache data before request:-----------------
    //        request data range:            ---
    late HttpServer server;
    late VideoCacheServer videoCacheServer;
    try {
      int expectedLength = testFileSize;
      videoCacheServer = VideoCacheServer(cacheDir: cacheDir, httpClient: HttpClient()..connectionTimeout = const Duration(seconds: 5));
      await videoCacheServer.start();

      server = await serve(testFilePath);
      String url = 'http://127.0.0.1:${server.port}';
      String proxyUrl = videoCacheServer.getProxyUrl(url);

      // prepare cached data
      await performRequest(0, 2097152, proxyUrl, expectedLength);
      // perform the testing request
      List<int>? actual = await performRequest(1048576, 1050624, proxyUrl, expectedLength);
      List<int> expected = await readFileInRange(testFilePath, 1048576, 1050624);
      expect(actual, expected);
      expect(videoCacheServer.caches[url]!.fragments.length, 1);
    } finally {
      unawaited(server.close());
      videoCacheServer.stop();
      unawaited(videoCacheServer.clear());
    }
  }, timeout: const Timeout(Duration(days: 1)));
  test('test range contained in the cache to the end', () async {
    //
    // cache data before request:-----------------
    //        request data range:              ---
    late HttpServer server;
    late VideoCacheServer videoCacheServer;
    try {
      int expectedLength = testFileSize;
      videoCacheServer = VideoCacheServer(cacheDir: cacheDir, httpClient: HttpClient()..connectionTimeout = const Duration(seconds: 5));
      await videoCacheServer.start();

      server = await serve(testFilePath);
      String url = 'http://127.0.0.1:${server.port}';
      String proxyUrl = videoCacheServer.getProxyUrl(url);

      // prepare cached data
      await performRequest(0, 2097152, proxyUrl, expectedLength);
      // perform the testing request
      List<int>? actual = await performRequest(1048576, 2097152, proxyUrl, expectedLength);
      List<int> expected = await readFileInRange(testFilePath, 1048576, 2097152);
      expect(actual, expected);
      expect(videoCacheServer.caches[url]!.fragments.length, 1);
    } finally {
      unawaited(server.close());
      videoCacheServer.stop();
      unawaited(videoCacheServer.clear());
    }
  }, timeout: const Timeout(Duration(days: 1)));
  test('test range contained in the cache from the beginning', () async {
    //
    // cache data before request:     -----------------
    //        request data range:     ---
    late HttpServer server;
    late VideoCacheServer videoCacheServer;
    try {
      int expectedLength = testFileSize;
      videoCacheServer = VideoCacheServer(cacheDir: cacheDir, httpClient: HttpClient()..connectionTimeout = const Duration(seconds: 5));
      await videoCacheServer.start();

      server = await serve(testFilePath);
      String url = 'http://127.0.0.1:${server.port}';
      String proxyUrl = videoCacheServer.getProxyUrl(url);

      // prepare cached data
      await performRequest(1048576, 3147776, proxyUrl, expectedLength);
      // perform the testing request
      List<int>? actual = await performRequest(1048576, 2097152, proxyUrl, expectedLength);
      List<int> expected = await readFileInRange(testFilePath, 1048576, 2097152);
      expect(actual, expected);
      expect(videoCacheServer.caches[url]!.fragments.length, 1);
    } finally {
      unawaited(server.close());
      videoCacheServer.stop();
      unawaited(videoCacheServer.clear());
    }
  }, timeout: const Timeout(Duration(days: 1)));
  test('test range crosses the beginning of the cache', () async {
    //
    // cache data before request:     ----------------
    //        request data range:   ---
    late HttpServer server;
    late VideoCacheServer videoCacheServer;
    try {
      int expectedLength = testFileSize;
      videoCacheServer = VideoCacheServer(cacheDir: cacheDir, httpClient: HttpClient()..connectionTimeout = const Duration(seconds: 5));
      await videoCacheServer.start();

      server = await serve(testFilePath);
      String url = 'http://127.0.0.1:${server.port}';
      String proxyUrl = videoCacheServer.getProxyUrl(url);

      // prepare cached data
      await performRequest(2097152, 3145728, proxyUrl, expectedLength);
      // perform the testing request
      List<int>? actual = await performRequest(1048576, 2099200, proxyUrl, expectedLength);
      List<int> expected = await readFileInRange(testFilePath, 1048576, 2099200);
      expect(actual, expected);
      expect(videoCacheServer.caches[url]!.fragments.length, 2);
    } finally {
      unawaited(server.close());
      videoCacheServer.stop();
      unawaited(videoCacheServer.clear());
    }
  }, timeout: const Timeout(Duration(days: 1)));
  test('test range crosses the end of the cache', () async {
    //
    // cache data before request:----------------
    //        request data range:               ---
    late HttpServer server;
    late VideoCacheServer videoCacheServer;
    try {
      int expectedLength = testFileSize;
      videoCacheServer = VideoCacheServer(cacheDir: cacheDir, httpClient: HttpClient()..connectionTimeout = const Duration(seconds: 5));
      await videoCacheServer.start();

      server = await serve(testFilePath);
      String url = 'http://127.0.0.1:${server.port}';
      String proxyUrl = videoCacheServer.getProxyUrl(url);

      // prepare cached data
      await performRequest(0, 2097152, proxyUrl, expectedLength);
      // perform the testing request
      List<int>? actual = await performRequest(1048576, 2099200, proxyUrl, expectedLength);
      List<int> expected = await readFileInRange(testFilePath, 1048576, 2099200);
      expect(actual, expected);
      expect(videoCacheServer.caches[url]!.fragments.length, 2);
    } finally {
      unawaited(server.close());
      videoCacheServer.stop();
      unawaited(videoCacheServer.clear());
    }
  }, timeout: const Timeout(Duration(days: 1)));
  test('test range contains cache in middle', () async {
    //
    // cache data before request:          -----
    //        request data range:        ----------
    late HttpServer server;
    late VideoCacheServer videoCacheServer;
    try {
      int expectedLength = testFileSize;
      videoCacheServer = VideoCacheServer(cacheDir: cacheDir, httpClient: HttpClient()..connectionTimeout = const Duration(seconds: 5));
      await videoCacheServer.start();

      server = await serve(testFilePath);
      String url = 'http://127.0.0.1:${server.port}';
      String proxyUrl = videoCacheServer.getProxyUrl(url);

      // prepare cached data
      await performRequest(1050624, 2097152, proxyUrl, expectedLength);
      // perform the testing request
      List<int>? actual = await performRequest(1048576, 2099200, proxyUrl, expectedLength);
      List<int> expected = await readFileInRange(testFilePath, 1048576, 2099200);
      expect(actual, expected);
      expect(videoCacheServer.caches[url]!.fragments.length, 3);
    } finally {
      unawaited(server.close());
      videoCacheServer.stop();
      unawaited(videoCacheServer.clear());
    }
  }, timeout: const Timeout(Duration(days: 1)));
  test('test range contains the cache from the beginning', () async {
    //
    // cache data before request:        -----
    //        request data range:        ----------
    late HttpServer server;
    late VideoCacheServer videoCacheServer;
    try {
      int expectedLength = testFileSize;
      videoCacheServer = VideoCacheServer(cacheDir: cacheDir, httpClient: HttpClient()..connectionTimeout = const Duration(seconds: 5));
      await videoCacheServer.start();

      server = await serve(testFilePath);
      String url = 'http://127.0.0.1:${server.port}';
      String proxyUrl = videoCacheServer.getProxyUrl(url);

      // prepare cached data
      await performRequest(1048576, 2097152, proxyUrl, expectedLength);
      // perform the testing request
      List<int>? actual = await performRequest(1048576, 2099200, proxyUrl, expectedLength);
      List<int> expected = await readFileInRange(testFilePath, 1048576, 2099200);
      expect(actual, expected);
      expect(videoCacheServer.caches[url]!.fragments.length, 2);
    } finally {
      unawaited(server.close());
      videoCacheServer.stop();
      unawaited(videoCacheServer.clear());
    }
  }, timeout: const Timeout(Duration(days: 1)));
  test('test range contains the cache to the end', () async {
    //
    // cache data before request:             -----
    //        request data range:        ----------
    late HttpServer server;
    late VideoCacheServer videoCacheServer;
    try {
      int expectedLength = testFileSize;
      videoCacheServer = VideoCacheServer(cacheDir: cacheDir, httpClient: HttpClient()..connectionTimeout = const Duration(seconds: 5));
      await videoCacheServer.start();

      server = await serve(testFilePath);
      String url = 'http://127.0.0.1:${server.port}';
      String proxyUrl = videoCacheServer.getProxyUrl(url);

      // prepare cached data
      await performRequest(2097152, 2099200, proxyUrl, expectedLength);
      // perform the testing request
      List<int>? actual = await performRequest(1048576, 2099200, proxyUrl, expectedLength);
      List<int> expected = await readFileInRange(testFilePath, 1048576, 2099200);
      expect(actual, expected);
      expect(videoCacheServer.caches[url]!.fragments.length, 2);
    } finally {
      unawaited(server.close());
      videoCacheServer.stop();
      unawaited(videoCacheServer.clear());
    }
  }, timeout: const Timeout(Duration(days: 1)));
  test('test range stays out of cache', () async {
    //
    // cache data before request:----------------
    //        request data range:                  ---
    late HttpServer server;
    late VideoCacheServer videoCacheServer;
    try {
      int expectedLength = testFileSize;
      videoCacheServer = VideoCacheServer(cacheDir: cacheDir, httpClient: HttpClient()..connectionTimeout = const Duration(seconds: 5));
      await videoCacheServer.start();

      server = await serve(testFilePath);
      String url = 'http://127.0.0.1:${server.port}';
      String proxyUrl = videoCacheServer.getProxyUrl(url);

      // prepare cached data
      await performRequest(0, 2097152, proxyUrl, expectedLength);
      // perform the testing request
      List<int>? actual = await performRequest(2099200, 2101248, proxyUrl, expectedLength);
      List<int> expected = await readFileInRange(testFilePath, 2099200, 2101248);
      expect(actual, expected);
      expect(videoCacheServer.caches[url]!.fragments.length, 2);
    } finally {
      unawaited(server.close());
      videoCacheServer.stop();
      unawaited(videoCacheServer.clear());
    }
  }, timeout: const Timeout(Duration(days: 1)));
  test('test range sticks discontinuously to the cache', () async {
    //
    // cache data before request:----------------  --- ---
    //        request data range:               ---------
    late HttpServer server;
    late VideoCacheServer videoCacheServer;
    try {
      int expectedLength = testFileSize;
      videoCacheServer = VideoCacheServer(cacheDir: cacheDir, httpClient: HttpClient()..connectionTimeout = const Duration(seconds: 5));
      await videoCacheServer.start();

      server = await serve(testFilePath);
      String url = 'http://127.0.0.1:${server.port}';
      String proxyUrl = videoCacheServer.getProxyUrl(url);

      // prepare cached data range 1
      await performRequest(0, 2097152, proxyUrl, expectedLength);
      // prepare cached data range 2
      await performRequest(2099200, 3147776, proxyUrl, expectedLength);
      // prepare cached data range 3
      await performRequest(3149824, null, proxyUrl, expectedLength);
      // perform the testing request
      List<int>? actual = await performRequest(2095104, 3151872, proxyUrl, expectedLength);
      List<int> expected = await readFileInRange(testFilePath, 2095104, 3151872);
      expect(actual, expected);
      expect(videoCacheServer.caches[url]!.fragments.length, 5);
    } finally {
      unawaited(server.close());
      videoCacheServer.stop();
      unawaited(videoCacheServer.clear());
    }
  }, timeout: const Timeout(Duration(days: 1)));
}
