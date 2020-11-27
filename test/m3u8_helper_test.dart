import 'package:flutter_test/flutter_test.dart';
import 'package:video_cache_server/src/m3u8_helper.dart';
import 'dart:io';

void main() {
  group('proxyM3u8Content', () {
    String testDataDir = 'test_resources/m3u8/';
    var loadData = (String name) => File('$testDataDir$name.txt').readAsStringSync();
    var proxy = (String raw) => 'http://127.0.0.1:8888/?url=${Uri.encodeComponent(raw)}';
    var testM3u8 = (String name, List<String> expectedPlaylists) {
      Uri uri = Uri.parse('https://test.com/m3u8/$name.m3u8');
      M3u8 actual = proxyM3u8Content(loadData(name), proxy, uri);
      expect(actual.proxied, File('$testDataDir${name}_expected.txt').readAsStringSync().replaceAll('\r', ''), reason: 'test $name should match.');
      expect(actual.playlists, expectedPlaylists);
    };
    test('living', () async {
      String name = 'living';
      testM3u8(
        name,
        [
          'https://test.com/m3u8/fileSequence1.ts',
          'https://test.com/fileSequence2.ts',
          'http://media.anywhere.com/fileSequence3.ts',
          'http://media.anywhere.com/stream/fileSequence4.ts',
          'https://media.anywhere.com/stream/fileSequence5.ts',
          'https://media.anywhere.com/stream/fileSequence6.ts',
        ],
      );
    });
    test('#EXT-X-STREAM-INF', () async {
      String name = 'ext-x-stream-inf';
      testM3u8(
        name,
        [
          'https://test.com/m3u8/1000k/hls/1.m3u8',
          'https://test.com/1000k/hls/2.m3u8',
          'https://media.anywhere.com/1000k/hls/3.m3u8',
        ],
      );
    });
    test('contains URI', () async {
      String name = 'uri';
      testM3u8(
        name,
        [
          'https://test.com/m3u8/eng/prog_index.m3u8',
          'https://test.com/m3u8/fre/prog_index.m3u8',
          'https://test.com/m3u8/sp/prog_index.m3u8',
          'https://test.com/m3u8/low/iframe.m3u8',
          'https://test.com/m3u8/low/iframe.m3u8',
        ],
      );
    });
    test('Playlist with Encrypted Media Segments', () async {
      String name = 'encrypted_media_segments';
      testM3u8(name, [
        'http://media.example.com/fileSequence52-A.ts',
        'http://media.example.com/fileSequence52-B.ts',
        'http://media.example.com/fileSequence52-C.ts',
        'http://media.example.com/fileSequence53-A.ts',
      ],);
    });
  });
  group('isM3u8', () {
    var _test = (String contentType, Uri uri, bool expected) {
      bool actual = isM3u8(contentType, uri);
      expect(actual, expected);
    };
    test('content-type: application/x-mpegURL', () async {
      _test('application/x-mpegURL', null, true);
    });
    test('content-type: application/x-mpegurl', () async {
      _test('application/x-mpegURL', null, true);
    });
    test('content-type: vnd.apple.mpegURL', () async {
      _test('application/x-mpegURL', null, true);
    });
    test('content-type: vnd.apple.mpegurl', () async {
      _test('application/x-mpegURL', null, true);
    });
    test('extension: .m3u8 without queries', () async {
      _test('text/plain', Uri.parse('http://devimages.apple.com/iphone/samples/bipbop/bipbopall.m3u8'), true);
    });
    test('extension: .m3u8 with queries', () async {
      _test('text/plain', Uri.parse('http://devimages.apple.com/iphone/samples/bipbop/bipbopall.m3u8?dev=true'), true);
    });
    test('extension: .M3U8', () async {
      _test('text/plain', Uri.parse('http://devimages.apple.com/iphone/samples/bipbop/bipbopall.M3U8'), true);
    });
    test('content-type: illegal', () async {
      _test('application/mpegURL', Uri.parse('http://devimages.apple.com/iphone/samples/bipbop/bipbopall.M3U'), false);
    });
    test('uri contains .m3u8 but is not the extension', () async {
      _test('text/plain', Uri.parse('http://devimages.apple.com/iphone/samples/bipbop/bipbopall.m3u8/'), false);
    });
  });
}
