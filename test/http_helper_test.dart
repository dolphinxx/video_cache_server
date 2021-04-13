import 'package:flutter_test/flutter_test.dart';
import 'package:video_cache_server/src/http_helper.dart';

void main() {
  group('RequestRange', () {
    var _test = (String? value, RequestRange expected) {
      RequestRange actual = RequestRange.parse(value);
      expect(actual.specified, expected.specified, reason: 'specified should be equal.');
      expect(actual.begin, expected.begin, reason: 'begin should be equal.');
      expect(actual.end, expected.end, reason: 'end should be equal.');
      expect(actual.suffixLength, expected.suffixLength, reason: 'suffixLength should be equal.');
    };
    test('with begin & end', () async {
      String value = 'bytes=10-1024';
      RequestRange expected = RequestRange.unspecified()
        ..specified = true
        ..begin = 10
        ..end = 1024;
      _test(value, expected);
    });
    test('begin only', () async {
      String value = 'bytes=10-';
      RequestRange expected = RequestRange.unspecified()
        ..specified = true
        ..begin = 10;
      _test(value, expected);
    });
    test('suffix length', () async {
      String value = 'bytes=-1024';
      RequestRange expected = RequestRange.unspecified()
        ..specified = true
        ..suffixLength = 1024;
      _test(value, expected);
    });
    test('null value', () async {
      String? value;
      RequestRange expected = RequestRange.unspecified();
      _test(value, expected);
    });
    test('empty value', () async {
      String value = '';
      RequestRange expected = RequestRange.unspecified();
      _test(value, expected);
    });
    test('invalid value', () async {
      String value = 'bytes=1024';
      RequestRange expected = RequestRange.unspecified();
      _test(value, expected);
    });
    test('multiple range set', () async {
      String value = 'bytes=0-1024,1024-2048,2048-';
      RequestRange expected = RequestRange.unspecified()
        ..specified = true
        ..begin = 0
        ..end = 1024;
      _test(value, expected);
    });
  });
  group('ResponseRange', () {
    var _test = (String? value, ResponseRange expected) {
      ResponseRange actual = ResponseRange.parse(value);
      expect(actual.specified, expected.specified, reason: 'specified should be equal.');
      expect(actual.begin, expected.begin, reason: 'begin should be equal.');
      expect(actual.end, expected.end, reason: 'end should be equal.');
      expect(actual.size, expected.size, reason: 'size should be equal.');
    };
    test('normal', () async {
      String value = 'bytes 10-1024/1025';
      ResponseRange expected = ResponseRange.unspecified()
        ..specified = true
        ..begin = 10
        ..end = 1024
        ..size = 1025;
      _test(value, expected);
    });
    test('without size', () async {
      String value = 'bytes 10-1024/*';
      ResponseRange expected = ResponseRange.unspecified()
        ..specified = true
        ..begin = 10
        ..end = 1024;
      _test(value, expected);
    });
    test('range not satisfiable', () async {
      String value = 'bytes */1025';
      ResponseRange expected = ResponseRange.unspecified();
      _test(value, expected);
    });
    test('null value', () async {
      String? value;
      ResponseRange expected = ResponseRange.unspecified();
      _test(value, expected);
    });
    test('empty value', () async {
      String value = '';
      ResponseRange expected = ResponseRange.unspecified();
      _test(value, expected);
    });
    test('invalid value - without begin', () async {
      String value = 'bytes -1024/1025';
      ResponseRange expected = ResponseRange.unspecified();
      _test(value, expected);
    });
    test('invalid value - without end', () async {
      String value = 'bytes 10-/1025';
      ResponseRange expected = ResponseRange.unspecified();
      _test(value, expected);
    });
  });
  group('appendQuery', () {
    var _test = (String url, String queries, expected) {
      expect(appendQuery(url, queries), expected);
    };
    test('+anchor +queries', () {
      _test('https://www.example.com?a=1#test', 'b=2&c=3', 'https://www.example.com?a=1&b=2&c=3#test');
    });
    test('+anchor -? -queries', () {
      _test('https://www.example.com#test', 'b=2&c=3', 'https://www.example.com?b=2&c=3#test');
    });
    test('+anchor +? -queries', () {
      _test('https://www.example.com?#test', 'b=2&c=3', 'https://www.example.com?b=2&c=3#test');
    });
    test('-anchor +queries', () {
      _test('https://www.example.com?a=1', 'b=2&c=3', 'https://www.example.com?a=1&b=2&c=3');
    });
    test('-anchor endsWith & +queries', () {
      _test('https://www.example.com?a=1&', 'b=2&c=3', 'https://www.example.com?a=1&b=2&c=3');
    });
    test('-anchor -? -queries', () {
      _test('https://www.example.com', 'b=2&c=3', 'https://www.example.com?b=2&c=3');
    });
    test('-anchor +? -queries', () {
      _test('https://www.example.com?', 'b=2&c=3', 'https://www.example.com?b=2&c=3');
    });
  });
}
