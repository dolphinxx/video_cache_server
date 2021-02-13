// Copyright (c) 2020, dolphinxx <bravedolphinxx@gmail.com>. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:pedantic/pedantic.dart';

/// Take a range of bytes from a `Stream<List<int>>`.
class ByteRangeStream {
  /// Take a range of bytes from the [source] stream.
  ///
  /// The [begin] of the range is inclusive and default to 0 which will start at the beginning of the source stream.
  ///
  /// The [end] of the stream is exclusive, and if a null value is provided, the taking will walk forward until reaches the end of the source or when the subscription is cancelled.
  static Stream<List<int>> range(Stream<List<int>> source, {int begin = 0, int end}) {
    StreamController<List<int>> controller = StreamController();
    StreamSubscription<List<int>> subscription;
    bool passThrough = begin == 0 && end == null;
    int walked = 0;
    bool finished = false;
    int transferred = 0;
    int expected = end == null ? null : end - begin;

    List<int> _transformData(List<int> data) {
      if (passThrough) {
        return data;
      }
      int blockBegin = walked;
      int blockEnd = walked + data.length;
      int _walked = walked;
      walked += data.length;
      if (blockEnd <= begin) {
        // still far away
        return null;
      }
      if (end != null && blockBegin >= end) {
        // received all data in range
        finished = true;
        controller.close().then((value) => subscription.cancel());
        return null;
      }
      if (blockBegin < begin) {
        blockBegin = begin;
      }
      if (end == null) {
        return data.sublist(blockBegin - _walked);
      }
      if (blockEnd > end) {
        blockEnd = end;
      }
      return blockEnd - blockBegin == data.length ? data : data.sublist(blockBegin - _walked, blockEnd - _walked);
    }

    controller.onListen = () {
      subscription = source.listen((List<int> event) {
        // print('---- onData');
        if (finished) {
          return;
        }
        List<int> targetData = _transformData(event);
        if (targetData == null) {
          return;
        }
        if (controller.isClosed) {
          return;
        }
        controller.add(targetData);
        transferred += targetData.length;
        if (expected != null && transferred > expected) {
          print('ByteRangeStream transfer exceeded, expected:$expected, transferred:$transferred');
        }
      }, onDone: () {
        // print('ByteRangeStream transferred:$transferred');
        controller.close();
      }, onError: (e, s) {
        // print('ByteRangeStream transferred:$transferred');
        controller.addError(e, s);
      });
    };
    controller.onResume = () {
      // print('---- onResume');
      subscription.resume();
    };
    controller.onPause = () {
      // print('---- onPause');
      subscription.pause();
    };
    controller.onCancel = () async {
      // print('---- onCancel');
      unawaited(controller.close());
      return subscription.cancel();
    };
    return controller.stream;
  }
}

// class ByteRangeStream extends Stream<List<int>>{
//   final Stream<List<int>> _source;
//   final int _begin;
//   final int _end;
//   /// take bytes in range [ [begin], [end]) from [_source]
//   ByteRangeStream(this._source, {int begin, int end}):_begin = begin??0,_end=end;
//
//   StreamSubscription<List<int>> listen(void Function(List<int> data) onData,
//       {Function onError, void Function() onDone, bool cancelOnError}) {
//     return new _ByteRangeStreamSubscription(
//         _source.listen(null, onError: onError, cancelOnError: cancelOnError), _begin, _end)
//       ..onData(onData)
//       ..onDone(onDone);
//   }
// }
//
// class _ByteRangeStreamSubscription implements StreamSubscription<List<int>> {
//   final StreamSubscription<List<int>> _source;
//   final int begin;
//   final int end;
//   final bool passThrough;
//   int walked = 0;
//   bool _isClosed = false;
//
//   /// Zone where listen was called.
//   final Zone _zone = Zone.current;
//
//   /// User's data handler.
//   void Function(List<int>) _handleData;
//
//   void Function() _onDone;
//   Future _cancelFuture;
//
//   _ByteRangeStreamSubscription(this._source, this.begin, this.end):passThrough = begin == 0 && end == null {
//     _source.onData(_onData);
//   }
//
//   @override
//   Future cancel() => _source.cancel();
//
//   void onData(void Function(List<int> data) handleData) {
//     _handleData = handleData == null
//         ? null
//         : _zone.registerUnaryCallback<dynamic, List<int>>(handleData);
//   }
//
//   void onError(Function handleError) {
//     _source.onError(handleError);
//   }
//
//   void onDone(void handleDone()) {
//     _onDone = handleDone;
//     _source.onDone(handleDone);
//   }
//
//   List<int> _transformData(List<int> data) {
//     if(passThrough) {
//       return data;
//     }
//     int _begin = walked;
//     int _end = walked + data.length;
//     int _walked = walked;
//     walked += data.length;
//     if(_end < begin) {
//       return null;
//     }
//     if(end != null && _begin >= end) {
//       // received all data in range
//       _isClosed = true;
//       _sendDone();
//       return null;
//     }
//     if(_begin < begin) {
//       _begin = begin;
//     }
//     if(end == null) {
//       return data.sublist(_begin - _walked);
//     }
//     if(_end > end) {
//       _end = end;
//     }
//     return _end - _begin == data.length ? data : data.sublist(_begin - _walked, _end - _walked);
//   }
//
//   void _onData(List<int> data) {
//     if (_isClosed || _handleData == null) return;
//     List<int> targetData = _transformData(data);
//     if(targetData == null) {
//       return;
//     }
//     _zone.runUnaryGuarded(_handleData, targetData);
//   }
//
//   void _cancel() {
//     _cancelFuture = cancel();
//   }
//
//   void _sendDone() {
//     void sendDone() {
//       if(_onDone != null) {
//         _zone.runGuarded(_onDone);
//       }
//     }
//
//     _cancel();
//     var cancelFuture = _cancelFuture;
//     if (cancelFuture != null) {
//       cancelFuture.whenComplete(sendDone);
//     } else {
//       sendDone();
//     }
//   }
//
//   void pause([Future resumeSignal]) {
//     _source.pause(resumeSignal);
//   }
//
//   void resume() {
//     _source.resume();
//   }
//
//   bool get isPaused => _source.isPaused;
//
//   Future<E> asFuture<E>([E futureValue]) => _source.asFuture<E>(futureValue);
// }
