import 'dart:async';

import 'package:synchronous_stream/src/controller.dart';
import 'package:test/test.dart';

void main() {
  group('SynchronousDispatchStreamController (single-subscription)', () {
    test('S1: emits single event', () async {
      final c = SynchronousDispatchStreamController<int>();
      expectLater(c.stream, emitsInOrder([1, emitsDone]));
      c.add(1);
      await c.close();
    });

    test('S2: emits multiple events in order', () async {
      final c = SynchronousDispatchStreamController<int>();
      expectLater(c.stream, emitsInOrder([1, 2, 3, emitsDone]));
      c
        ..add(1)
        ..add(2)
        ..add(3);
      await c.close();
    });

    test('S3: completes with done after close', () async {
      final c = SynchronousDispatchStreamController<void>();
      expectLater(c.stream, emitsDone);
      await c.close();
    });

    // test('S4: add after close throws StateError', () async {
    //   final c = SynchronousDispatchStreamController<int>();
    //   await c.close();
    //   expect(() => c.add(1), throwsStateError);
    // });

    test('S5: addError delivered to onError', () async {
      final c = SynchronousDispatchStreamController<void>();
      final errors = <Object>[];
      c.stream.listen(null, onError: errors.add);
      c.addError('boom');
      await c.close();
      expect(errors, ['boom']);
    });

    test('S6: addError provides stackTrace', () async {
      final c = SynchronousDispatchStreamController<void>();
      Object? gotError;
      StackTrace? gotStack;
      c.stream.listen(
        null,
        onError: (e, st) {
          gotError = e;
          gotStack = st;
        },
      );
      c.addError('oops', StackTrace.current);
      await c.close();
      expect(gotError, 'oops');
      expect(gotStack, isA<StackTrace>());
    });

    test('S7: listening twice throws StateError', () async {
      final c = SynchronousDispatchStreamController<int>();
      c.stream.listen((_) {});
      expect(() => c.stream.listen((_) {}), throwsStateError);
      await c.close();
    });

    test('S8: pause/resume buffers events', () async {
      final c = SynchronousDispatchStreamController<int>();
      final received = <int>[];
      final sub = c.stream.listen(received.add);
      sub.pause();
      c
        ..add(1)
        ..add(2);
      expect(received, isEmpty);
      sub.resume();
      await c.close();
      expect(received, [1, 2]);
    });

    test('S10: onListen called once', () async {
      var count = 0;
      final c = SynchronousDispatchStreamController<int>()..onListen = () => count++;
      c.stream.listen((_) {});
      await c.close();
      expect(count, 1);
    });

    test('S11: onCancel called when subscription canceled', () async {
      var canceled = false;
      final c = SynchronousDispatchStreamController<int>()..onCancel = () => canceled = true;
      final sub = c.stream.listen((_) {});
      await sub.cancel();
      await c.close();
      expect(canceled, isTrue);
    });

    test('S12: onPause and onResume invoked', () async {
      var paused = 0, resumed = 0;
      final c = SynchronousDispatchStreamController<int>()
        ..onPause = (() => paused++)
        ..onResume = () => resumed++;
      final sub = c.stream.listen((_) {});
      sub.pause();
      sub.resume();
      await c.close();
      expect(paused, 1);
      expect(resumed, 1);
    });

    test('S13: addStream forwards items in order', () async {
      final c = SynchronousDispatchStreamController<int>();
      final src = Stream.fromIterable([1, 2, 3]);
      expectLater(c.stream, emitsInOrder([1, 2, 3, emitsDone]));
      await c.addStream(src);
      await c.close();
    });

    test(
      'S14: addStream continues after error when cancelOnError=false',
      () async {
        final c = SynchronousDispatchStreamController<int>();
        final src = Stream<int>.multi((em) {
          em.add(1);
          em.addError('e');
          em.add(2);
          em.close();
        });
        final received = <Object?>[];
        c.stream.listen(received.add, onError: received.add);
        await c.addStream(src, cancelOnError: false);
        await c.close();
        expect(received, [1, 'e', 2]);
      },
    );

    test('S15: addStream stops on error when cancelOnError=true', () async {
      final c = SynchronousDispatchStreamController<int>();
      final src = Stream<int>.multi((em) {
        em.add(1);
        em.addError('e');
        em.add(2); // should not reach
        em.close();
      });
      final received = <Object?>[];
      c.stream.listen(received.add, onError: received.add);
      await c.addStream(src, cancelOnError: true);
      await c.close();
      expect(received, [1, 'e']);
    });

    test('S16: sink.add forwards', () async {
      final c = SynchronousDispatchStreamController<int>();
      expectLater(c.stream, emitsInOrder([42, emitsDone]));
      c.sink.add(42);
      await c.sink.close();
    });

    test('S17: sink.addError forwards', () async {
      final c = SynchronousDispatchStreamController<void>();
      Object? error;
      c.stream.listen(null, onError: (e, _) => error = e);
      c.sink.addError('bad');
      await c.close();
      expect(error, 'bad');
    });

    test('S21: map transform preserves done', () async {
      final c = SynchronousDispatchStreamController<int>();
      expectLater(c.stream.map((e) => e * 2), emitsInOrder([2, 4, emitsDone]));
      c
        ..add(1)
        ..add(2);
      await c.close();
    });

    test(
      'S23: hasListener true while subscribed and false after cancel',
      () async {
        final c = SynchronousDispatchStreamController<int>();
        expect(c.hasListener, isFalse);
        final sub = c.stream.listen((_) {});
        expect(c.hasListener, isTrue);
        await sub.cancel();
        expect(c.hasListener, isFalse);
        await c.close();
      },
    );

    test('S24: pause with resume signal future', () async {
      final c = SynchronousDispatchStreamController<int>();
      final received = <int>[];
      final sub = c.stream.listen(received.add);
      final resume = Future<void>.delayed(Duration(milliseconds: 10));
      sub.pause(resume);
      c
        ..add(1)
        ..add(2);
      await resume;
      await c.close();
      expect(received, [1, 2]);
    });

    test('S25: addStream with empty source completes', () async {
      final c = SynchronousDispatchStreamController<int>();
      final src = Stream<int>.empty();
      expectLater(c.stream, emitsDone);
      await c.addStream(src);
      await c.close();
    });
  });

  group('SynchronousDispatchStreamController.broadcast', () {
    test('B1: multiple listeners receive events', () async {
      final c = SynchronousDispatchStreamController<int>.broadcast();
      final a = <int>[], b = <int>[];
      c.stream.listen(a.add);
      c.stream.listen(b.add);
      c
        ..add(1)
        ..add(2);
      await c.close();
      expect(a, [1, 2]);
      expect(b, [1, 2]);
    });

    test('B2: pre-listen events are dropped', () async {
      final c = SynchronousDispatchStreamController<int>.broadcast();
      c
        ..add(1)
        ..add(2);
      final received = <int>[];
      c.stream.listen(received.add);
      await c.close();
      expect(received, isEmpty);
    });

    test('B4: addError delivered to listeners with onError', () async {
      final c = SynchronousDispatchStreamController<void>.broadcast();
      final errs1 = <Object>[], errs2 = <Object>[];
      c.stream.listen(null, onError: errs1.add);
      c.stream.listen(null, onError: errs2.add);
      c.addError('boom');
      await c.close();
      expect(errs1, ['boom']);
      expect(errs2, ['boom']);
    });

    test('B5: close completes all listeners', () async {
      final c = SynchronousDispatchStreamController<int>.broadcast();
      final d1 = expectLater(c.stream, emitsDone);
      final d2 = expectLater(c.stream, emitsDone);
      await c.close();
      await Future.wait([d1, d2]);
    });

    test('B6: pause buffers only for paused subscription', () async {
      final c = SynchronousDispatchStreamController<int>.broadcast();
      final a = <int>[], b = <int>[];
      final subA = c.stream.listen(a.add);
      final _ = c.stream.listen(b.add);
      subA.pause();
      c
        ..add(1)
        ..add(2);
      subA.resume();
      await c.close();
      expect(a, [1, 2]); // buffered during pause
      expect(b, [1, 2]); // received live
    });

    test('B7: onListen called once on first subscriber', () async {
      var count = 0;
      final c = SynchronousDispatchStreamController<int>.broadcast()..onListen = () => count++;
      c.stream.listen((_) {});
      c.stream.listen((_) {});
      await c.close();
      expect(count, 1);
    });

    test('B8: onCancel called when last subscriber cancels', () async {
      var calls = 0;
      final c = SynchronousDispatchStreamController<int>.broadcast()..onCancel = () => calls++;
      final a = c.stream.listen((_) {});
      final b = c.stream.listen((_) {});
      await a.cancel();
      expect(calls, 0);
      await b.cancel();
      await c.close();
      expect(calls, 1);
    });

    test('B9: addStream distributes to all listeners', () async {
      final c = SynchronousDispatchStreamController<int>.broadcast();
      final src = Stream.fromIterable([1, 2, 3]);
      final a = <int>[], b = <int>[];
      c.stream.listen(a.add);
      c.stream.listen(b.add);
      await c.addStream(src);
      await c.close();
      expect(a, [1, 2, 3]);
      expect(b, [1, 2, 3]);
    });

    test('B10: addStream stops on error when cancelOnError=true', () async {
      final c = SynchronousDispatchStreamController<int>.broadcast();
      final src = Stream<int>.multi((em) {
        em.add(1);
        em.addError('e');
        em.add(2);
        em.close();
      });
      final a = <Object?>[];
      final b = <Object?>[];
      c.stream.listen(a.add, onError: a.add);
      c.stream.listen(b.add, onError: b.add);
      await c.addStream(src, cancelOnError: true);
      await c.close();
      expect(a, [1, 'e']);
      expect(b, [1, 'e']);
    });

    test('B11: sink.add delivers to all', () async {
      final c = SynchronousDispatchStreamController<int>.broadcast();
      final a = <int>[], b = <int>[];
      c.stream.listen(a.add);
      c.stream.listen(b.add);
      c.sink.add(7);
      await c.close();
      expect(a, [7]);
      expect(b, [7]);
    });

    test('B12: sink.addError delivered to all with onError', () async {
      final c = SynchronousDispatchStreamController<void>.broadcast();
      final e1 = <Object>[], e2 = <Object>[];
      c.stream.listen(null, onError: e1.add);
      c.stream.listen(null, onError: e2.add);
      c.sink.addError('bad');
      await c.close();
      expect(e1, ['bad']);
      expect(e2, ['bad']);
    });

    test('B13: isClosed becomes true after close', () async {
      final c = SynchronousDispatchStreamController<void>.broadcast();
      expect(c.isClosed, isFalse);
      await c.close();
      expect(c.isClosed, isTrue);
    });

    test('B14: hasListener toggles with subscribers', () async {
      final c = SynchronousDispatchStreamController<int>.broadcast();
      expect(c.hasListener, isFalse);
      final a = c.stream.listen((_) {});
      expect(c.hasListener, isTrue);
      await a.cancel();
      expect(c.hasListener, isFalse);
      await c.close();
    });

    test('B15: multiple listens allowed', () async {
      final c = SynchronousDispatchStreamController<int>.broadcast();
      c.stream.listen((_) {});
      c.stream.listen((_) {});
      await c.close();
    });

    test('B16: late listener receives only future events', () async {
      final c = SynchronousDispatchStreamController<int>.broadcast();
      final early = <int>[], late = <int>[];
      c.stream.listen(early.add);
      c.add(1);
      c.stream.listen(late.add);
      c.add(2);
      await c.close();
      expect(early, [1, 2]);
      expect(late, [2]);
    });

    test('B17: cancel is idempotent', () async {
      final c = SynchronousDispatchStreamController<int>.broadcast();
      final sub = c.stream.listen((_) {});
      await sub.cancel();
      await sub.cancel(); // second cancel should not throw
      await c.close();
    });

    test('B18: resume without prior pause is a no-op', () async {
      final c = SynchronousDispatchStreamController<int>.broadcast();
      final sub = c.stream.listen((_) {});
      // ignore: deprecated_member_use (resume without pause is fine)
      sub.resume();
      c.add(1);
      await c.close();
    });

    test('B19: add after close throws', () async {
      final c = SynchronousDispatchStreamController<int>.broadcast();
      await c.close();
      expect(() => c.add(1), throwsStateError);
    });

    test('B20: addStream after close throws', () async {
      final c = SynchronousDispatchStreamController<int>.broadcast();
      await c.close();
      expect(() => c.addStream(Stream.value(1)), throwsStateError);
    });

    test('B21: new listener after close receives immediate done', () async {
      final c = SynchronousDispatchStreamController<int>.broadcast();
      await c.close();
      await expectLater(c.stream, emitsDone);
    });

    test('B22: stream is broadcast', () async {
      final c = SynchronousDispatchStreamController<int>.broadcast();
      expect(c.stream.isBroadcast, isTrue);
      await c.close();
    });

    test(
      'B23: adding with no listeners does not throw (events dropped)',
      () async {
        final c = SynchronousDispatchStreamController<int>.broadcast();
        c
          ..add(1)
          ..add(2);
        await c.close();
      },
    );

    test(
      'B24: cancelOnError on one listener cancels only that subscription',
      () async {
        final c = SynchronousDispatchStreamController<int>.broadcast();
        final a = <Object?>[], b = <Object?>[];
        c.stream.listen(a.add, onError: a.add, cancelOnError: true);
        c.stream.listen(b.add, onError: b.add, cancelOnError: false);
        c
          ..add(1)
          ..addError('e')
          ..add(2);
        await c.close();
        // First listener should have received 1 then error, and canceled (no 2)
        // Second listener should receive all
        expect(a, [1, 'e']);
        expect(b, [1, 'e', 2]);
      },
    );

    test('B25: where/map transforms still close with done', () async {
      final c = SynchronousDispatchStreamController<int>.broadcast();
      final transformed = c.stream.where((e) => e.isEven).map((e) => e * 10);
      expectLater(transformed, emitsInOrder([20, emitsDone]));
      c
        ..add(1)
        ..add(2);
      await c.close();
    });
  });
}
