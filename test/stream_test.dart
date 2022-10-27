import 'package:flutter_test/flutter_test.dart';

import 'dart:async';
import 'dart:developer' show log;

void main() {
  test('Error in onData - asFuture', () async {
    Stream stream = Stream.periodic(const Duration(milliseconds: 500), (c) => c);
    late StreamSubscription subscription;
    try {
      subscription = stream.listen((event) {
        log('onData - $event');
        if (event as int > 4) {
          throw 'Boom!';
        }
      }, onError: (e, s) => log('onError - $e'));
      await subscription.asFuture();
    } catch (e, s) {
      log('caughtError - $e\n$s');
    }
    unawaited(subscription.cancel());
    log('done.');
  }, skip: "the error thrown in onData can't be caught when using asFuture.");
  test('Error in onData - Completer', () async {
    Stream stream = Stream.periodic(const Duration(milliseconds: 500), (c) => c);
    late StreamSubscription subscription;
    Completer completer = Completer();
    try {
      subscription = stream.listen(
        (event) {
          try {
            log('onData - $event');
            if (event as int > 4) {
              throw 'Boom!';
            }
          } catch (e, s) {
            completer.completeError(e, s);
          }
        },
        onError: (Object e, StackTrace s) {
          log('onError - $e');
          completer.completeError(e, s);
        },
        onDone: () {
          completer.complete();
        },
      );
      await await completer.future;
    } catch (e, s) {
      log('caughtError - $e\n$s');
    }
    unawaited(subscription.cancel());
    log('done.');
  });
  test('controller onCancel', () async {
    late StreamController controller;
    controller = StreamController(onListen: () {
      int i = 0;
      Timer.periodic(const Duration(milliseconds: 100), (timer) {
        int ii = i++;
        log('writing $ii');
        try {
          controller.add(ii);
          log('written $ii');
        } catch (e) {
          log('before close..');
          controller.close();
          log('after close..');
        }
        if(i > 5) {
          timer.cancel();
          log('before close...');
          controller.close();
          log('after close...');
        }
      });
    }, onCancel: () async {
      log('onCancel start... isClosed:${controller.isClosed}');
      await Future.delayed(const Duration(seconds: 1));
      log('onCancel finished.');
    });
    await controller.stream.skip(2).first;
    log('cancelled after read.');
    await Future.delayed(const Duration(seconds: 3));
    log('before close. isClosed:${controller.isClosed}');
    unawaited(controller.close());
    log('after close. isClosed:${controller.isClosed}');
    await Future.delayed(const Duration(seconds: 10));
  });
  test('controller onError', () async {
    late StreamController controller;
    controller = StreamController(onListen: () {
      int i = 0;
      Timer.periodic(const Duration(milliseconds: 100), (timer) {
        try {
          int ii = i++;
          if(ii > 10) {
            timer.cancel();
            return;
          }
          if(ii > 5) {
            log('before addError...');
            controller.addError('$ii exceeded');
            log('after addError...');
            return;
          }
          log('writing $ii');
          controller.add(ii);
          log('written $ii');
        } catch (e) {
          log('Error in Timer.periodic callback $e');
        }
      });
    }, onCancel: () async {
      log('onCancel start... isClosed:${controller.isClosed}');
    });
    try {
      await controller.stream.last;
    } catch (e, s) {
      log('failed to wait for last element.', error: e, stackTrace: s);
    }
    log('cancelled after read.');
    log('before close. isClosed:${controller.isClosed}');
    unawaited(controller.close());
    log('after close. isClosed:${controller.isClosed}');
    await Future.delayed(const Duration(seconds: 10));
    log('isClosed: ${controller.isClosed}');
  });
  test('controller close', () async {
    late StreamController controller;
    controller = StreamController(onListen: () async {
      await Future.delayed(const Duration(seconds: 1));
      controller.add(1);
      await Future.delayed(const Duration(seconds: 1));
      controller.add(2);
      await Future.delayed(const Duration(seconds: 1));
      unawaited(controller.close());
      await Future.delayed(const Duration(seconds: 1));
      unawaited(controller.close());
    }, onCancel: () async {
      log('onCancel start... isClosed:${controller.isClosed}');
      await Future.delayed(const Duration(seconds: 3));
    });
    try {
      var data = await controller.stream.last;
      log('data - $data');
    } catch (e, s) {
      log('failed to wait for last element.', error: e, stackTrace: s);
    }
    log('cancelled after read.');
    log('before close. isClosed:${controller.isClosed}');
    unawaited(controller.close());
    log('after close. isClosed:${controller.isClosed}');
    await Future.delayed(const Duration(seconds: 10));
    log('isClosed: ${controller.isClosed}');
  });
}
