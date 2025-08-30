import 'dart:async';

import 'package:synchronous_stream/src/controller.dart';
import 'package:test/test.dart';

void main() {
  group('SynchronousDispatchStreamController (single-subscription) — more', () {
    test('S27: length completes with number of data events', () async {
      final c = SynchronousDispatchStreamController<int>();
      c
        ..add(1)
        ..add(2)
        ..add(3);
      unawaited(c.close());
      final len = await c.stream.length;
      expect(len, 3);
    });

    test('S28: length completes with error if stream errors', () async {
      final c = SynchronousDispatchStreamController<int>();
      unawaited(
        Future(() {
          c
            ..add(1)
            ..addError('e')
            ..add(2);
          c.close();
        }),
      );
      await expectLater(c.stream.length, throwsA('e'));
    });

    test('S30: last returns last element', () async {
      final c = SynchronousDispatchStreamController<int>();
      c
        ..add(1)
        ..add(2)
        ..add(3);
      unawaited(c.close());
      expect(await c.stream.last, 3);
    });

    test('S33: onCancel async waits for completion of cancel()', () async {
      var done = false;
      final c = SynchronousDispatchStreamController<int>()
        ..onCancel = () async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          done = true;
        };
      final sub = c.stream.listen((_) {});
      final f = sub.cancel();
      expect(done, isFalse);
      await f;
      expect(done, isTrue);
      await c.close();
    });

    test('S34: closing while paused delays done until resume', () async {
      final c = SynchronousDispatchStreamController<int>();
      var finished = false;
      final sub = c.stream.listen((_) {}, onDone: () => finished = true);

      sub.pause();
      final closeFut = c.close();
      expect(finished, isFalse);

      // Still not finished while paused.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(finished, isFalse);

      sub.resume();
      await closeFut;
      expect(finished, isTrue);
    });

    test('S35: sync:true delivers events immediately', () async {
      final c = SynchronousDispatchStreamController<int>();
      var seen = false;
      c.stream.listen((_) {
        seen = true;
      });
      c.add(1);
      expect(seen, isTrue);
      await c.close();
    });

    test('S36: sync:true allows reentrant add keeping order', () async {
      final c = SynchronousDispatchStreamController<int>();
      final out = <int>[];
      c.stream.listen((e) {
        out.add(e);
        if (e == 1) c.add(2);
      });
      c.add(1);
      await c.close();
      expect(out, [1, 2]);
    });

    test(
      'S37: default async controller also preserves order on reentrant add',
      () async {
        final c = SynchronousDispatchStreamController<int>();
        final out = <int>[];
        c.stream.listen((e) {
          out.add(e);
          if (e == 1) c.add(2);
        });
        c.add(1);
        await c.close();
        expect(out, [1, 2]);
      },
    );

    test('S38: controller with nullable type accepts null', () async {
      final c = SynchronousDispatchStreamController<int?>();
      final out = <int?>[];
      c.stream.listen(out.add);
      c
        ..add(null)
        ..add(1);
      await c.close();
      expect(out, [null, 1]);
    });

    test('S39: cast<int> from num emits TypeError on wrong type', () async {
      final c = SynchronousDispatchStreamController<num>();
      final errors = <Object>[];
      c.stream.cast<int>().listen((_) {}, onError: errors.add);
      c.add(3.14); // wrong type for cast<int>
      await c.close();
      expect(errors.single, isA<TypeError>());
    });

    test('S40: transform can convert errors into data', () async {
      final c = SynchronousDispatchStreamController<int>();
      final transformed = c.stream.transform<int>(
        StreamTransformer.fromHandlers(
          handleData: (e, sink) => sink.add(e * 10),
          handleError: (e, st, sink) => sink.add(999),
        ),
      );
      expectLater(transformed, emitsInOrder([10, 999, emitsDone]));
      c
        ..add(1)
        ..addError('bad');
      await c.close();
    });

    test('S41: drain completes with provided value', () async {
      final c = SynchronousDispatchStreamController<int>();
      c
        ..add(1)
        ..add(2);
      final result = c.stream.drain<String>('ok');
      await c.close();
      expect(await result, 'ok');
    });

    test('S42: addError after close throws StateError', () async {
      final c = SynchronousDispatchStreamController<int>();
      await c.close();
      expect(() => c.addError('nope'), throwsStateError);
    });

    test(
      'S43: listener throws — error captured by zone, stream continues',
      () async {
        final errors = <Object>[];
        await runZonedGuarded(() async {
          final c = SynchronousDispatchStreamController<int>();
          final out = <int>[];
          c.stream.listen((e) {
            if (e == 1) {
              throw 'boom';
            }
            out.add(e);
          });
          c
            ..add(1)
            ..add(2);
          await c.close();
          expect(out, [2]);
        }, (e, _) => errors.add(e));
        expect(errors, contains('boom'));
      },
    );

    test('S44: addStream after close throws StateError', () async {
      final c = SynchronousDispatchStreamController<int>();
      await c.close();
      expect(() => c.addStream(Stream.value(1)), throwsStateError);
    });
  });

  group('SynchronousDispatchStreamController.broadcast — more', () {
    test('B26: addStream with no listeners drops all source events', () async {
      final c = SynchronousDispatchStreamController<int>.broadcast();
      await c.addStream(Stream.fromIterable([1, 2, 3]));
      final out = <int>[];
      c.stream.listen(out.add);
      await c.close();
      expect(out, isEmpty);
    });

    test('B27: onCancel async waits when last listener cancels', () async {
      var cancelled = false;
      final c = SynchronousDispatchStreamController<int>.broadcast()
        ..onCancel = () async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          cancelled = true;
        };
      final sub = c.stream.listen((_) {});
      final f = sub.cancel();
      expect(cancelled, isFalse);
      await f;
      expect(cancelled, isTrue);
      await c.close();
    });

    test('B29: sync:true delivers immediately to all listeners', () async {
      final c = SynchronousDispatchStreamController<int>.broadcast();
      var aSeen = false, bSeen = false;
      c.stream.listen((_) => aSeen = true);
      c.stream.listen((_) => bSeen = true);
      c.add(1);
      expect(aSeen, isTrue);
      expect(bSeen, isTrue);
      await c.close();
    });

    test(
      'B31: cast<int> produces TypeError on wrong type to all listeners with onError',
      () async {
        final c = SynchronousDispatchStreamController<num>.broadcast();
        final e1 = <Object>[], e2 = <Object>[];
        c.stream.cast<int>().listen((_) {}, onError: e1.add);
        c.stream.cast<int>().listen((_) {}, onError: e2.add);
        c.add(3.14);
        await c.close();
        expect(e1.single, isA<TypeError>());
        expect(e2.single, isA<TypeError>());
      },
    );

    test('B32: where/map pipeline behaves and closes with done', () async {
      final c = SynchronousDispatchStreamController<int>.broadcast();
      final piped = c.stream.where((e) => e > 1).map((e) => e * 5);
      expectLater(piped, emitsInOrder([10, 15, emitsDone]));
      c
        ..add(1)
        ..add(2)
        ..add(3);
      await c.close();
    });

    test(
      'B33: events while nobody listens are dropped even between listeners',
      () async {
        final c = SynchronousDispatchStreamController<int>.broadcast();
        final out = <int>[];

        // First listener
        var sub = c.stream.listen(out.add);
        c.add(1);
        await sub.cancel(); // no listeners now
        c
          ..add(2)
          ..add(3); // both dropped
        // Second listener
        sub = c.stream.listen(out.add);
        c.add(4);
        await c.close();

        expect(out, [1, 4]);
      },
    );

    test(
      'B34: per-subscription buffering while paused (only paused one buffers)',
      () async {
        final c = SynchronousDispatchStreamController<int>.broadcast();
        final a = <int>[], b = <int>[];

        final subA = c.stream.listen(a.add);
        final _ = c.stream.listen(b.add);

        c.add(1); // both get 1

        subA.pause();
        c
          ..add(2)
          ..add(3); // A buffers [2,3], B gets live
        subA.resume();

        c.add(4);

        await c.close();
        expect(a, [1, 2, 3, 4]);
        expect(b, [1, 2, 3, 4]);
      },
    );

    test(
      'B35: late subscriber only sees future events even with sync:true',
      () async {
        final c = SynchronousDispatchStreamController<int>.broadcast();
        final early = <int>[], late = <int>[];
        c.stream.listen(early.add);
        c.add(1);
        c.stream.listen(late.add);
        c.add(2);
        await c.close();
        expect(early, [1, 2]);
        expect(late, [2]);
      },
    );

    test('B36: add after last cancel but before close is dropped', () async {
      final c = SynchronousDispatchStreamController<int>.broadcast();
      final out = <int>[];
      final sub = c.stream.listen(out.add);
      c.add(1);
      await sub.cancel();
      c.add(2); // dropped
      await c.close();
      expect(out, [1]);
    });

    test('B37: pause() with erroring future still resumes delivery', () async {
      final c = SynchronousDispatchStreamController<int>.broadcast();
      final out = <int>[];
      final sub = c.stream.listen(out.add);

      final resume = Future<void>.error('x');
      sub.pause(resume);
      c
        ..add(1)
        ..add(2);
      try {
        await resume;
      } catch (_) {
        // ignore error; should still resume
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await c.close();

      expect(out, [1, 2]);
    });

    test('B38: onListen called exactly once (first subscriber)', () async {
      var onListenCount = 0;
      final c = SynchronousDispatchStreamController<int>.broadcast()
        ..onListen = () => onListenCount++;
      c.stream.listen((_) {});
      c.stream.listen((_) {});
      await c.close();
      expect(onListenCount, 1);
    });

    test('B40: onListen can enqueue initial events synchronously', () async {
      final c = SynchronousDispatchStreamController<int>.broadcast();
      c.onListen = () {
        // enqueue initial
        c
          ..add(10)
          ..add(20);
      };
      final out = <int>[];
      c.stream.listen(out.add);
      await c.close();
      expect(out, [10, 20]);
    });
  });
}
