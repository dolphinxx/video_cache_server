// Copyright (c) 2020, dolphinxx <bravedolphinxx@gmail.com>. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:pedantic/pedantic.dart';

import './byte_range_stream.dart';
import './http_helper.dart';
import './io_client.dart';
import './io_streamed_response.dart';

typedef SubscriptionSetter = void Function(StreamSubscription<List<int>> subscription);
typedef DataFetcher = Future<CacheFragment> Function(int begin, int end, StreamController<List<int>> receiver);

// class ScheduledTask {
//   bool waiting = true;
//   bool responseDone = false;
//   Completer completer;
//   StreamSubscription subscription;
// }

class CacheInfo {
  final bool lazy;
  final String url;
  final List<CacheFragment> fragments = [];

  /// The index url this cache is belong to. For a `.ts` file cache, this is the url of the `m3u8` file containing it.
  final String? belongTo;
  int? current;
  int? total;
  Map<String, String>? headers;

  bool get finished => current == total;
  StreamSubscription? subscription;

  StreamController<List<int>>? _controller;
  Object? _entrantIdentity;

  Future<dynamic>? _lastEntrant;

  CacheInfo({
    required this.url,
    this.lazy = true,
    this.belongTo,
  });

  bool cached(RequestRange requestRange) {
    if (requestRange.begin == null || requestRange.end == null) {
      return finished;
    }
    int begin = requestRange.begin!;
    int end = requestRange.end! + 1;
    List<CacheFragment> rangesMatched = fragments
        .where((element) =>
            (element.begin >= begin && element.begin < end) || (element.end <= end && element.end > begin) || (element.begin < begin && element.end > end))
        .toList()
          ..sort((a, b) => a.begin - b.begin);
    if (rangesMatched.isEmpty) {
      return false;
    }
    for (CacheFragment range in rangesMatched) {
      if (range.begin > begin) {
        return false;
      }
      begin = range.end;
    }
    return begin >= end;
  }

  /// Creates a stream to serve data from [begin] to [end], data is read from cache.
  Stream<List<int>> streamFromCache({int begin = 0, int? end}) {
    late StreamController<List<int>> controller;
    StreamSubscription? $subscription;
    controller = StreamController(onListen: () async {
      // print(''Stream[$begin-$end] - onListen');
      try {
        int $begin = begin;
        // int _written = 0;
        for (CacheFragment fragment in List.of(fragments)..sort((a, b) => a.begin - b.begin)) {
          if ((end != null && fragment.begin >= end) || fragment.end <= $begin) {
            continue;
          }
          Completer subscriptionCompleter = Completer();
          int _relativeBegin = $begin - fragment.begin;
          int _relativeEnd = end == null ? fragment.received : math.min(end - fragment.begin, fragment.received);
          $subscription = fragment.file?.openRead(_relativeBegin, _relativeEnd).listen(
            (event) {
              try {
                if (controller.isClosed) {
                  subscriptionCompleter.complete();
                  return;
                }
                controller.add(event);
              } catch (e, s) {
                if (!subscriptionCompleter.isCompleted) {
                  subscriptionCompleter.completeError(e, s);
                }
              }
            },
            onError: (Object e, StackTrace s) {
              if (!subscriptionCompleter.isCompleted) {
                subscriptionCompleter.completeError(e, s);
              }
            },
            onDone: () {
              if (!subscriptionCompleter.isCompleted) {
                subscriptionCompleter.complete();
              }
            },
          );
          try {
            await subscriptionCompleter.future;
          } finally {
            try {
              await $subscription?.cancel();
            } catch (_) {}
          }
          $begin += _relativeEnd - _relativeBegin;
          // _written += _relativeEnd - _relativeBegin;
          if (end != null && $begin >= end) {
            break;
          }
        }
        // print('--[$begin-$end] written:$_written');
      } catch (e, s) {
        if (!controller.isClosed) {
          controller.addError(e, s);
        }
      }
      unawaited(controller.close());
    }, onPause: () {
      // print('Stream[$begin-$end] - onPause');
      $subscription?.pause();
    }, onResume: () {
      // print('Stream[$begin-$end] - onResume');
      $subscription?.resume();
    }, onCancel: () async {
      // print('Stream[$begin-$end] - onCancel');
      unawaited(controller.close());
    });
    return controller.stream;
  }

  /// Synchronous the [_stream] entry
  Future<Stream<List<int>>> stream({
    int begin = 0,
    int? end,
    required File Function() createFragmentFile,
    IOStreamedResponse? clientResponse,
    required IOClient client,
    required http.Request clientRequest,
  }) async {
    Future? prev = _lastEntrant;
    Completer completer = Completer.sync();
    _lastEntrant = completer.future;

    if (prev != null) {
      await prev;
    }
    Stream<List<int>> result =
        _stream(begin: begin, end: end, createFragmentFile: createFragmentFile, clientRequest: clientRequest, clientResponse: clientResponse, client: client);
    if (identical(_lastEntrant, completer.future)) {
      _lastEntrant = null;
    }
    completer.complete();
    return result;
  }

  /// Creates a stream to serve the data from [begin] to [end], data may be from cache or remote.
  Stream<List<int>> _stream({
    int begin = 0,
    int? end,
    required File Function() createFragmentFile,
    IOStreamedResponse? clientResponse,
    required IOClient client,
    required http.Request clientRequest,
  }) {
    _controller?.close();
    Object entrantIdentity = _entrantIdentity = Object();
    late StreamController<List<int>> controller;
    controller = _controller = StreamController<List<int>>(onListen: () async {
      // print(''Stream[$begin-$end] - onListen');
      if (!identical(entrantIdentity, _entrantIdentity)) {
        unawaited(controller.close());
        return;
      }
      fragments.sort((a, b) => a.begin - b.begin);
      // whether wake next is executed
      try {
        await _writeData(
          begin: begin,
          end: end,
          previousResponse: clientResponse,
          createFragmentFile: createFragmentFile,
          client: client,
          clientRequest: clientRequest,
          controller: controller,
          recursive: false,
        );
      } catch (e, s) {
        if (!controller.isClosed) {
          controller.addError(e, s);
        }
      }
      unawaited(controller.close());
    }, onPause: () {
      // print('Stream[$begin-$end] - onPause');
      if (lazy != false) {
        subscription?.pause();
      }
    }, onResume: () {
      // print('Stream[$begin-$end] - onResume');
      if (lazy != false) {
        subscription?.resume();
      }
    }, onCancel: () async {
      // print('Stream[$begin-$end] - onCancel');
      unawaited(controller.close());
    });
    return controller.stream;
  }

  /// [end] may be null when the response from remote doesn't provide a content-length.
  Future<void> _writeData({
    required int begin,
    int? end,
    IOStreamedResponse? previousResponse,
    required File Function() createFragmentFile,
    required IOClient client,
    required http.Request clientRequest,
    required StreamController<List<int>> controller,
    bool recursive = false,
  }) async {
    CacheFragment? fragment = fragments.firstWhereOrNull((element) => element.contains(begin));
    if (fragment == null) {
      // fetch from remote
      CacheFragment? nextFragment = fragments.firstWhereOrNull((element) => element.begin > begin);

      int? _end = end == null ? nextFragment?.begin : (nextFragment != null ? math.min(nextFragment.begin, end) : end);

      // print('Reading from remote - [$begin-$_end, url:$url]');
      File cacheFile = createFragmentFile();
      cacheFile.parent.createSync(recursive: true);
      fragment = CacheFragment(begin: begin, end: begin, file: cacheFile, expected: _end != null ? _end - begin : -1);
      fragments.add(fragment);
      IOSink sink = cacheFile.openWrite(mode: FileMode.write);
      try {
        http.StreamedResponse _clientResponse;
        // the original response is not read, and response range is not specified(meaning full data), or its range includes fetcher's range
        if (previousResponse != null) {
          _clientResponse = previousResponse;
          previousResponse = null;
        } else {
          http.Request _request = cloneRequest(clientRequest);
          _request.headers['range'] = 'bytes=$begin-${_end == null ? "" : _end - 1}';
          // print('====== Proxy Fetcher Request ======');
          // print('Url:$realUrl\nMethod:${_request.method}');
          // _request.headers.forEach((key, value) => print('Header:$key=$value'));
          // print('===========================');
          _clientResponse = await client.send(_request);
          // print('====== Proxy Fetcher Response ======');
          // _clientResponse.headers.forEach((key, value) {
          //   print('Header:$key=$value');
          // });
          // print('============================');
        }
        Stream<List<int>> stream = _clientResponse.stream;
        ResponseRange _range = ResponseRange.parse(_clientResponse.headers['content-range']);
        if (_range.specified) {
          // range begin relative to the ranged response stream
          int _$begin;
          if (_range.begin != null) {
            _$begin = begin - _range.begin!;
          } else {
            _$begin = begin;
          }
          stream = ByteRangeStream.range(stream, begin: _$begin, end: fragment.expected != -1 ? _$begin + fragment.expected : null);
        } else if (begin > 0 || _end != null) {
          stream = ByteRangeStream.range(stream, begin: begin, end: begin + fragment.expected);
        }
        int transferred = 0;

        Completer _subscriptionCompleter = Completer();
        // using subscription to control stream's pause/resume
        StreamSubscription<List<int>> subscription = stream.listen(
          (element) {
            try {
              if (controller.isClosed) {
                _subscriptionCompleter.complete();
                return;
              }
              transferred += element.length;
              if (fragment!.expected != -1 && transferred > fragment.expected) {
                print('fetcher data[$begin-$end] exceeded, expected:${fragment.expected}, transferred:$transferred');
              }
              controller.add(element);
              sink.add(element);
              current = current! + element.length;
              fragment.end += element.length;
            } catch (e, s) {
              if (!_subscriptionCompleter.isCompleted) {
                _subscriptionCompleter.completeError(e, s);
              }
            }
          },
          onDone: () {
            if (total == null && begin == 0 && end == null) {
              // the remote response does not provide the content-length field, and we successfully and completely consumed the data.
              // Therefore the received data length is considered as the content-length.
              total = transferred;
            }
            if (!_subscriptionCompleter.isCompleted) {
              _subscriptionCompleter.complete();
            }
          },
          onError: (Object e, StackTrace s) {
            if (!_subscriptionCompleter.isCompleted) {
              _subscriptionCompleter.completeError(e, s);
            }
          },
        );
        this.subscription = subscription;
        try {
          await _subscriptionCompleter.future;
        } finally {
          try {
            // suppress cancel_subscriptions warning
            await subscription.cancel();
          } catch (_) {}
        }

        // print('Read finished from remote - [$begin-$_end, url:$url]');
        await sink.flush();
      } finally {
        try {
          await sink.close();
        } catch (_) {}
        if (fragment.received == 0) {
          fragments.remove(fragment);
          if (fragment.file!.existsSync()) {
            fragment.file!.deleteSync();
          }
        }
      }
    } else {
      // read from cache file
      int __end = end == null ? fragment.end : math.min(end, fragment.end);
      // print('Reading from cache - [$begin-$__end, url:$url]');
      Stream<List<int>> stream = fragment.file!.openRead(begin - fragment.begin, __end - fragment.begin);

      Completer _subscriptionCompleter = Completer();
      // using subscription to control stream's pause/resume
      StreamSubscription subscription = stream.listen(
        (event) {
          try {
            if (controller.isClosed) {
              _subscriptionCompleter.complete();
              return;
            }
            controller.add(event);
          } catch (e, s) {
            if (!_subscriptionCompleter.isCompleted) {
              _subscriptionCompleter.completeError(e, s);
            }
          }
        },
        onDone: () {
          if (!_subscriptionCompleter.isCompleted) {
            _subscriptionCompleter.complete();
          }
        },
        onError: (Object e, StackTrace s) {
          if (!_subscriptionCompleter.isCompleted) {
            _subscriptionCompleter.completeError(e, s);
          }
        },
      );
      this.subscription = subscription;
      try {
        await _subscriptionCompleter.future;
      } finally {
        try {
          // suppress cancel_subscriptions warning
          await subscription.cancel();
        } catch (_) {}
      }
      // print('Read finished from cache - [$begin-$__end, url:$url]');
    }
    subscription = null;
    if ((end != null && fragment.end >= end)) {
      // reached the end.
      // print('Writing data[$begin-$end] - reached the end.');
      return;
    }
    if (end == null && fragment.received == 0) {
      // end is not specified and last request received empty data, meaning reached the end.
      // print('Writing data[$begin-$end] - reached the end.');
      return;
    }
    if (controller.hasListener && !controller.isClosed && !controller.isPaused) {
      // need to read more fragments
      await _writeData(
        begin: fragment.end,
        end: end,
        previousResponse: previousResponse,
        createFragmentFile: createFragmentFile,
        client: client,
        clientRequest: clientRequest,
        controller: controller,
        recursive: true,
      );
    }
  }

  CacheInfo.fromMap(Map map)
      : url = map['url'] as String,
        lazy = map['lazy'] as bool,
        belongTo = map['belongTo'] == null ? null : map['belongTo'] as String {
    fragments.addAll((map['fragments'] as List).map((e) => CacheFragment.fromMap(e as Map<dynamic, dynamic>)));
    current = map['current'] as int;
    total = map['total'] as int;
    if (map['headers'] != null) {
      headers = (map['headers'] as Map).cast<String, String>();
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'lazy': lazy,
      'url': url,
      'belongTo': belongTo,
      'fragments': fragments,
      'current': current,
      'total': total,
      'headers': headers,
    };
  }

  Map<String, dynamic> toJson() {
    return toMap();
  }
}

class CacheFragment {
  File? file;
  late int begin;
  late int end;

  /// received byte count
  int get received => end - begin;

  /// the expected byte count
  late int expected;

  bool contains(int begin) => this.begin <= begin && end > begin;

  Map<String, dynamic> toMap() {
    return {
      'file': file?.path,
      'begin': begin,
      'end': end,
      'expected': expected,
    };
  }

  Map<String, dynamic> toJson() {
    return toMap();
  }

  CacheFragment({required this.begin, required this.end, this.file, this.expected=0});

  CacheFragment.fromMap(Map map) {
    file = map['file'] != null ? File(map['file'] as String) : null;
    begin = map['begin'] as int;
    end = map['end'] as int;
    expected = map['expected'] as int;
  }
}
