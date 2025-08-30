import 'dart:async';

import 'package:synchronous_stream/src/controller.dart';
import 'package:test/test.dart';

void main() {
  group('SynchronousDispatchStreamController - synchronous semantics', () {
    test('N1: delivers synchronously before add() returns', () async {
      final c = SynchronousDispatchStreamController<int>();
      final log = <String>[];
      c.stream.listen((e) => log.add('data:$e'));

      log.add('before');
      c.add(1);
      log.add('after');

      await c.close();
      expect(log, ['before', 'data:1', 'after']);
    });

    test('N2: reentrant add from onData keeps order', () async {
      final c = SynchronousDispatchStreamController<int>();
      final out = <int>[];
      late StreamSubscription<int> sub;
      sub = c.stream.listen((e) {
        out.add(e);
        if (e == 1) c.add(2);
      });

      c.add(1);
      await sub.cancel();
      await c.close();
      expect(out, [1, 2]);
    });

    test(
      'N3: changing onData handler mid-stream takes effect immediately',
      () async {
        final c = SynchronousDispatchStreamController<int>();
        final a = <int>[], b = <int>[];

        final sub = c.stream.listen((e) => a.add(e));
        c.add(1); // handled by A

        sub.onData((e) => b.add(e));
        c
          ..add(2) // handled by B
          ..add(3); // handled by B

        await sub.cancel();
        await c.close();

        expect(a, [1]);
        expect(b, [2, 3]);
      },
    );

    test('N4: changing onError handler mid-stream', () async {
      final c = SynchronousDispatchStreamController<int>();
      final errs1 = <Object>[], errs2 = <Object>[];

      final sub = c.stream.listen((_) {}, onError: errs1.add);
      c.addError('e1');
      sub.onError(errs2.add);
      c.addError('e2');

      await sub.cancel();
      await c.close();
      expect(errs1, ['e1']);
      expect(errs2, ['e2']);
    });

    test('N5: setting onDone and then replacing it', () async {
      final c = SynchronousDispatchStreamController<int>();
      var firstDone = false, secondDone = false;

      final sub = c.stream.listen((_) {}, onDone: () => firstDone = true);
      sub.onDone(() => secondDone = true);
      await c.close();

      expect(firstDone, isFalse);
      expect(secondDone, isTrue);
      await sub.cancel();
    });

    test('N6: pause/resume buffers events while paused', () async {
      final c = SynchronousDispatchStreamController<int>();
      final got = <int>[];
      final sub = c.stream.listen(got.add);

      sub.pause();
      c
        ..add(1)
        ..add(2);
      expect(got, isEmpty, reason: 'no delivery while paused');

      sub.resume();
      await c.close();
      expect(got, [1, 2]);
    });

    test('N7: pause with resume-future waits until future completes', () async {
      final c = SynchronousDispatchStreamController<int>();
      final got = <int>[];
      final sub = c.stream.listen(got.add);

      final resume = Future<void>.delayed(const Duration(milliseconds: 10));
      sub.pause(resume);
      c
        ..add(1)
        ..add(2);
      expect(got, isEmpty);

      await resume; // resume triggers now
      await Future<void>.microtask(() {});
      await c.close();
      expect(got, [1, 2]);
    });

    test('N8: subscription.isPaused toggles', () async {
      final c = SynchronousDispatchStreamController<int>();
      final sub = c.stream.listen((_) {});
      expect(sub.isPaused, isFalse);
      sub.pause();
      expect(sub.isPaused, isTrue);
      sub.resume();
      expect(sub.isPaused, isFalse);
      await sub.cancel();
      await c.close();
    });

    test('N9: cancel stops further delivery', () async {
      final c = SynchronousDispatchStreamController<int>();
      final got = <int>[];
      final sub = c.stream.listen(got.add);

      c.add(1);
      await sub.cancel();
      c
        ..add(2)
        ..add(3);

      await c.close();
      expect(got, [1]);
    });

    test('N10: add after close throws StateError', () async {
      final c = SynchronousDispatchStreamController<int>();
      await c.close();
      expect(() => c.add(1), throwsStateError);
    });

    test('N11: addError after close throws StateError', () async {
      final c = SynchronousDispatchStreamController<int>();
      await c.close();
      expect(() => c.addError('e'), throwsStateError);
    });

    test('N12: close is idempotent', () async {
      final c = SynchronousDispatchStreamController<void>();
      final f1 = c.close();
      final f2 = c.close();
      await Future.wait([f1, f2]);
    });

    test('N13a: first returns first element', () async {
      final c = SynchronousDispatchStreamController<int>();

      final firstF = c.stream.first; // подписались
      c
        ..add(10)
        ..add(20)
        ..add(30);
      await c.close();

      expect(await firstF, 10);
    });

    test('N13b: last returns last element', () async {
      final c = SynchronousDispatchStreamController<int>();

      final lastF = c.stream.last; // подписались
      c
        ..add(10)
        ..add(20)
        ..add(30);
      await c.close();

      expect(await lastF, 30);
    });

    test('N13c: length counts all data events', () async {
      final c = SynchronousDispatchStreamController<int>();

      final lenF = c.stream.length; // подписались
      c
        ..add(10)
        ..add(20)
        ..add(30);
      await c.close();

      expect(await lenF, 3);
    });

    test('N14: single succeeds with exactly one element', () async {
      final c = SynchronousDispatchStreamController<int>();
      final singleF = c.stream.single;
      c.add(7);
      await c.close();
      expect(await singleF, 7);
    });

    test('N16: any/every/contains short-circuit as expected', () async {
      final c = SynchronousDispatchStreamController<int>.broadcast();
      final anyF = c.stream.any((x) => x == 2);
      final everyF = c.stream.every((x) => x < 3);
      final containsF = c.stream.contains(3);

      c
        ..add(1)
        ..add(2)
        ..add(3);
      await c.close();

      expect(await anyF, isTrue);
      expect(await everyF, isFalse);
      expect(await containsF, isTrue);
    });

    test('N17: elementAt picks correct index', () async {
      final c = SynchronousDispatchStreamController<int>();
      final f = c.stream.elementAt(2);
      c
        ..add(5)
        ..add(6)
        ..add(7);
      await c.close();
      expect(await f, 7);
    });

    test('N18: transform handleError can convert errors into data', () async {
      final c = SynchronousDispatchStreamController<int>();
      final transformed = c.stream.transform<int>(
        StreamTransformer.fromHandlers(
          handleData: (e, sink) => sink.add(e * 10),
          handleError: (e, st, sink) => sink.add(999),
        ),
      );

      final expectF = expectLater(
        transformed,
        emitsInOrder([10, 999, emitsDone]),
      );
      c
        ..add(1)
        ..addError('boom');
      await c.close();
      await expectF;
    });

    test('N19: handleError(test:) filters which errors are handled', () async {
      final c = SynchronousDispatchStreamController<void>();
      final handled = <Object>[];
      final passedThrough = <Object>[];

      // Подписка ДО эмитов. handleError ловит только StateError,
      // остальные попадут в onError слушателя.
      c.stream
          .handleError(handled.add, test: (e) => e is StateError)
          .listen((_) {}, onError: passedThrough.add);

      c.addError(ArgumentError('a')); // не должен быть перехвачен handleError
      c.addError(StateError('s')); // должен быть перехвачен handleError
      await c.close();

      expect(handled.length, 1);
      expect(handled.single, isA<StateError>());

      expect(passedThrough.length, 1);
      expect(passedThrough.single, isA<ArgumentError>());
    });

    test('N20: unhandled addError is reported to zone', () async {
      final c = SynchronousDispatchStreamController<void>();
      Object? captured;
      await runZonedGuarded(() async {
        c.stream.listen((_) {}); // no onError
        c.addError('err');
        await c.close();
      }, (e, _) => captured = e);
      expect(captured, 'err');
    });

    test('N21: onData(null) stops forwarding data to listener', () async {
      final c = SynchronousDispatchStreamController<int>();
      final got = <int>[];
      final sub = c.stream.listen(got.add);

      c.add(1);
      sub.onData(null); // drop further data for this subscription
      c
        ..add(2)
        ..add(3);
      await sub.cancel();
      await c.close();

      expect(got, [1]);
    });

    test('N22: pause inside onData defers later events until resume', () async {
      final c = SynchronousDispatchStreamController<int>();
      final got = <int>[];
      late StreamSubscription<int> sub;

      sub = c.stream.listen((e) {
        got.add(e);
        if (e == 1) {
          sub.pause();
          c
            ..add(2)
            ..add(3);
          // Resume after scheduling microtask to simulate later.
          scheduleMicrotask(() => sub.resume());
        }
      });

      c.add(1);
      await Future<void>.delayed(const Duration(milliseconds: 1));
      await sub.cancel();
      await c.close();

      expect(got, [1, 2, 3]);
    });

    test(
      'N23: map/where pipeline stays synchronous relative to add()',
      () async {
        final c = SynchronousDispatchStreamController<int>();
        final log = <String>[];
        c.stream.where((e) => e.isEven).map((e) => e * 10).listen((e) {
          log.add('mapped:$e');
        });

        log.add('before');
        c
          ..add(1) // filtered
          ..add(2); // becomes 20
        log.add('after');

        await c.close();
        expect(log, ['before', 'mapped:20', 'after']);
      },
    );

    test('N24: changing onError to null makes errors unhandled', () async {
      final c = SynchronousDispatchStreamController<void>();
      Object? zoneError;
      final sub = c.stream.listen((_) {}, onError: (_) {});

      sub.onError(null); // no error handler anymore

      await runZonedGuarded(() async {
        c.addError('boom');
        await c.close();
      }, (e, _) => zoneError = e);

      expect(zoneError, 'boom');
    });

    test(
      'N25: onDone is invoked after buffered events drain on resume+close',
      () async {
        final c = SynchronousDispatchStreamController<int>();
        final got = <int>[];
        var done = false;

        final sub = c.stream.listen(got.add, onDone: () => done = true);
        sub.pause();

        c
          ..add(1)
          ..add(2);

        final closeF = c.close();
        expect(
          done,
          isFalse,
          reason: 'closed while paused does not call onDone yet',
        );

        sub.resume();
        await closeF;

        expect(got, [1, 2]);
        expect(done, isTrue);
      },
    );

    // test(
    //   'N26: cancelOnError=true cancels subscription on first error',
    //   () async {
    //     final c = SynchronousDispatchStreamController<int>();
    //     final seen = <Object?>[];

    //     final sub = c.stream.listen(
    //       seen.add,
    //       onError: seen.add,
    //       cancelOnError: true,
    //     );
    //     c
    //       ..add(1)
    //       ..addError('err')
    //       ..add(2); // should not be delivered

    //     await sub.asFuture<void>().catchError((_) {});
    //     await c.close();
    //     expect(seen, [1, 'err']);
    //   },
    // );

    test(
      'N27: multiple subscribers are not allowed (single-subscription)',
      () async {
        final c = SynchronousDispatchStreamController<int>();
        c.stream.listen((_) {});
        expect(() => c.stream.listen((_) {}), throwsStateError);
        await c.close();
      },
    );

    test('N28: stream getter returns the same instance', () async {
      final c = SynchronousDispatchStreamController<int>();
      final s1 = c.stream;
      final s2 = c.stream;
      expect(identical(s1, s2), isTrue);
      await c.close();
    });

    test(
      'N29: events sent before first listen are buffered and delivered',
      () async {
        final c = SynchronousDispatchStreamController<int>();
        c
          ..add(1)
          ..add(2);

        final got = <int>[];
        c.stream.listen(got.add);
        await c.close();

        expect(got, [1, 2]);
      },
    );

    test('N30: length throws if stream emits an error', () async {
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
  });
}
