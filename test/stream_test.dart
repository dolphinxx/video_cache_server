import 'package:flutter_test/flutter_test.dart';

import 'dart:async';

import 'package:pedantic/pedantic.dart';

void main() {
  test('Error in onData - asFuture', () async {
    Stream stream = Stream.periodic(Duration(milliseconds: 500), (c) => c);
    late StreamSubscription subscription;
    try {
      subscription = stream.listen((event) {
        print('onData - $event');
        if (event as int > 4) {
          throw 'Boom!';
        }
      }, onError: (e, s) => print('onError - $e'));
      await subscription.asFuture();
    } catch (e, s) {
      print('caughtError - $e\n$s');
    }
    unawaited(subscription.cancel());
    print('done.');
  }, skip: "the error thrown in onData can't be caught when using asFuture.");
  test('Error in onData - Completer', () async {
    Stream stream = Stream.periodic(Duration(milliseconds: 500), (c) => c);
    late StreamSubscription subscription;
    Completer completer = Completer();
    try {
      subscription = stream.listen(
        (event) {
          try {
            print('onData - $event');
            if (event as int > 4) {
              throw 'Boom!';
            }
          } catch (e, s) {
            completer.completeError(e, s);
          }
        },
        onError: (Object e, StackTrace s) {
          print('onError - $e');
          completer.completeError(e, s);
        },
        onDone: () {
          completer.complete();
        },
      );
      await await completer.future;
    } catch (e, s) {
      print('caughtError - $e\n$s');
    }
    unawaited(subscription.cancel());
    print('done.');
  });
  test('controller onCancel', () async {
    late StreamController controller;
    controller = StreamController(onListen: () {
      int i = 0;
      Timer.periodic(Duration(milliseconds: 100), (timer) {
        int _i = i++;
        print('writing $_i');
        try {
          controller.add(_i);
          print('written $_i');
        } catch (e) {
          print('before close..');
          controller.close();
          print('after close..');
        }
        if(i > 5) {
          timer.cancel();
          print('before close...');
          controller.close();
          print('after close...');
        }
      });
    }, onCancel: () async {
      print('onCancel start... isClosed:${controller.isClosed}');
      await Future.delayed(Duration(seconds: 1));
      print('onCancel finished.');
    });
    await controller.stream.skip(2).first;
    print('cancelled after read.');
    await Future.delayed(Duration(seconds: 3));
    print('before close. isClosed:${controller.isClosed}');
    unawaited(controller.close());
    print('after close. isClosed:${controller.isClosed}');
    await Future.delayed(Duration(seconds: 10));
  });
  test('controller onError', () async {
    late StreamController controller;
    controller = StreamController(onListen: () {
      int i = 0;
      Timer.periodic(Duration(milliseconds: 100), (timer) {
        try {
          int _i = i++;
          if(_i > 10) {
            timer.cancel();
            return;
          }
          if(_i > 5) {
            print('before addError...');
            controller.addError('$_i exceeded');
            print('after addError...');
            return;
          }
          print('writing $_i');
          controller.add(_i);
          print('written $_i');
        } catch (e) {
          print('Error in Timer.periodic callback $e');
        }
      });
    }, onCancel: () async {
      print('onCancel start... isClosed:${controller.isClosed}');
    });
    try {
      await controller.stream.last;
    } catch (e) {
      print(e);
    }
    print('cancelled after read.');
    print('before close. isClosed:${controller.isClosed}');
    unawaited(controller.close());
    print('after close. isClosed:${controller.isClosed}');
    await Future.delayed(Duration(seconds: 10));
    print('isClosed: ${controller.isClosed}');
  });
  test('controller close', () async {
    late StreamController controller;
    controller = StreamController(onListen: () async {
      await Future.delayed(Duration(seconds: 1));
      controller.add(1);
      await Future.delayed(Duration(seconds: 1));
      controller.add(2);
      await Future.delayed(Duration(seconds: 1));
      unawaited(controller.close());
      await Future.delayed(Duration(seconds: 1));
      unawaited(controller.close());
    }, onCancel: () async {
      print('onCancel start... isClosed:${controller.isClosed}');
      await Future.delayed(Duration(seconds: 3));
    });
    try {
      var data = await controller.stream.last;
      print('data - $data');
    } catch (e) {
      print(e);
    }
    print('cancelled after read.');
    print('before close. isClosed:${controller.isClosed}');
    unawaited(controller.close());
    print('after close. isClosed:${controller.isClosed}');
    await Future.delayed(Duration(seconds: 10));
    print('isClosed: ${controller.isClosed}');
  });
}
