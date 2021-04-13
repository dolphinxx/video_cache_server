import 'package:flutter_test/flutter_test.dart';
import 'package:video_cache_server/src/cache.dart';
import 'package:video_cache_server/src/http_helper.dart';

void main() {
  group('cached', () {
    test('single fragment - same', () async {
      CacheInfo cacheInfo = CacheInfo(url: '')..current=100..total=1000;
      cacheInfo.fragments.add(CacheFragment(begin:0, end: 100));
      RequestRange requestRange = RequestRange.unspecified()..begin=0..end=99;
      expect(cacheInfo.cached(requestRange), true);
    });
    test('multiple fragments - same', () async {
      CacheInfo cacheInfo = CacheInfo(url: '')..current=100..total=1000;
      cacheInfo.fragments.add(CacheFragment(begin: 0, end: 50));
      cacheInfo.fragments.add(CacheFragment(begin: 50, end: 100));
      RequestRange requestRange = RequestRange.unspecified()..begin=0..end=99;
      expect(cacheInfo.cached(requestRange), true);
    });
    test('multiple fragments - cross and contain', () async {
      CacheInfo cacheInfo = CacheInfo(url: '')..current=100..total=1000;
      cacheInfo.fragments.add(CacheFragment(begin: 0, end: 100));
      cacheInfo.fragments.add(CacheFragment(begin: 100, end: 200));
      cacheInfo.fragments.add(CacheFragment(begin: 200, end: 300));
      RequestRange requestRange = RequestRange.unspecified()..begin=50..end=250;
      expect(cacheInfo.cached(requestRange), true);
    });
    test('multiple fragments - cross and miss', () async {
      CacheInfo cacheInfo = CacheInfo(url: '')..current=100..total=1000;
      cacheInfo.fragments.add(CacheFragment(begin: 0, end: 100));
      cacheInfo.fragments.add(CacheFragment(begin: 100, end: 199));
      cacheInfo.fragments.add(CacheFragment(begin: 200, end: 300));
      RequestRange requestRange = RequestRange.unspecified()..begin=50..end=250;
      expect(cacheInfo.cached(requestRange), false);
    });
    test('single fragment - cross left', () async {
      CacheInfo cacheInfo = CacheInfo(url: '')..current=100..total=1000;
      cacheInfo.fragments.add(CacheFragment(begin: 100, end: 200));
      RequestRange requestRange = RequestRange.unspecified()..begin=0..end=150;
      expect(cacheInfo.cached(requestRange), false);
    });
    test('single fragment - cross right', () async {
      CacheInfo cacheInfo = CacheInfo(url: '')..current=100..total=1000;
      cacheInfo.fragments.add(CacheFragment(begin: 100, end: 200));
      RequestRange requestRange = RequestRange.unspecified()..begin=150..end=250;
      expect(cacheInfo.cached(requestRange), false);
    });
  });
}