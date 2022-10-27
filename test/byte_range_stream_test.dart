import 'package:flutter_test/flutter_test.dart';

import 'dart:async';
import 'dart:io';
import 'dart:developer' show log;

import 'package:video_cache_server/src/byte_range_stream.dart';

void main() {
  List<List<int>> generateData() {
    List<List<int>> data = [
      [],
      [],
      [],
    ];
    for (int i = 0; i < 30; i++) {
      data[i ~/ 10].add(i);
    }
    return data;
  }

  test('range starts and ends in the middle', () async {
    List<List<int>> data = generateData();
    Stream<List<int>> stream = Stream.fromIterable(data);
    int receivedCount = 0;
    List<int> received = [];
    stream = ByteRangeStream.range(stream, begin: 5, end: 15);
    Completer completer = Completer();
    stream.listen((element) {
      receivedCount += element.length;
      received.addAll(element);
      log('block:${element.length}');
    }, onError: (e, s) {
      log('Error\n$e\n$s');
    }, onDone: () {
      log('Done!');
      completer.complete();
    });
    await completer.future;
    log('received:$receivedCount');
    expect(receivedCount, 10);
    expect(received, [5, 6, 7, 8, 9, 10, 11, 12, 13, 14]);
  });
  test('range starts at left edge & ends in the middle', () async {
    List<List<int>> data = generateData();
    Stream<List<int>> stream = Stream.fromIterable(data);
    int receivedCount = 0;
    List<int> received = [];
    stream = ByteRangeStream.range(stream, begin: 0, end: 15);
    Completer completer = Completer();
    stream.listen((element) {
      receivedCount += element.length;
      received.addAll(element);
      log('block:${element.length}');
    }, onError: (e, s) {
      log('Error\n$e\n$s');
    }, onDone: () {
      log('Done!');
      completer.complete();
    });
    await completer.future;
    log('received:$receivedCount');
    expect(receivedCount, 15);
    expect(received, List.generate(15, (index) => index));
  });
  test('range starts at left edge & without ending', () async {
    List<List<int>> data = generateData();
    Stream<List<int>> stream = Stream.fromIterable(data);
    int receivedCount = 0;
    List<int> received = [];
    stream = ByteRangeStream.range(
      stream,
      begin: 0,
    );
    Completer completer = Completer();
    stream.listen((element) {
      receivedCount += element.length;
      received.addAll(element);
      log('block:${element.length}');
    }, onError: (e, s) {
      log('Error\n$e\n$s');
    }, onDone: () {
      log('Done!');
      completer.complete();
    });
    await completer.future;
    log('received:$receivedCount');
    List<int> expected = data.fold([], (previousValue, element) => previousValue..addAll(element));
    expect(receivedCount, expected.length);
    expect(received, expected);
  });
  test('range starts in the middle & without ending', () async {
    List<List<int>> data = generateData();
    Stream<List<int>> stream = Stream.fromIterable(data);
    int receivedCount = 0;
    List<int> received = [];
    stream = ByteRangeStream.range(
      stream,
      begin: 4,
    );
    Completer completer = Completer();
    stream.listen((element) {
      receivedCount += element.length;
      received.addAll(element);
      log('block:${element.length}');
    }, onError: (e, s) {
      log('Error\n$e\n$s');
    }, onDone: () {
      log('Done!');
      completer.complete();
    });
    await completer.future;
    log('received:$receivedCount');
    List<int> expected = data.fold<List<int>>(<int>[], (previousValue, element) => previousValue..addAll(element)).sublist(4);
    expect(receivedCount, expected.length);
    expect(received, expected);
  });
  test('with a exceeded end.', () async {
    List<List<int>> data = generateData();
    Stream<List<int>> stream = Stream.fromIterable(data);
    int receivedCount = 0;
    List<int> received = [];
    stream = ByteRangeStream.range(stream, begin: 4, end: 50);
    Completer completer = Completer();
    stream.listen((element) {
      receivedCount += element.length;
      received.addAll(element);
      log('block:${element.length}');
    }, onError: (e, s) {
      log('Error\n$e\n$s');
    }, onDone: () {
      log('Done!');
      completer.complete();
    });
    await completer.future;
    log('received:$receivedCount');
    List<int> expected = data.fold<List<int>>(<int>[], (previousValue, element) => previousValue..addAll(element)).sublist(4);
    expect(receivedCount, expected.length);
    expect(received, expected);
  });
  test('pass through', () async {
    List<List<int>> data = generateData();
    Stream<List<int>> stream = Stream.fromIterable(data);
    int receivedCount = 0;
    List<int> received = [];
    stream = ByteRangeStream.range(stream, begin: 0, end: 30);
    Completer completer = Completer();
    stream.listen((element) {
      receivedCount += element.length;
      received.addAll(element);
      log('block:${element.length}');
    }, onError: (e, s) {
      log('Error\n$e\n$s');
    }, onDone: () {
      log('Done!');
      completer.complete();
    });
    await completer.future;
    log('received:$receivedCount');
    List<int> expected = data.fold<List<int>>(<int>[], (previousValue, element) => previousValue..addAll(element));
    expect(receivedCount, expected.length);
    expect(received, expected);
  });
  test('read from file', () async {
    Stream<List<int>> stream = File('/tmp/test/hadoop-3.3.0-aarch64.tar.gz').openRead();
    int received = 0;
    stream = ByteRangeStream.range(stream, begin: 1024, end: 1024000);
    await stream.forEach((element) {
      received += element.length;
      log('block:${element.length}');
    });
    log('received:$received');
    expect(received, 1024000 - 1024);
  });
}
