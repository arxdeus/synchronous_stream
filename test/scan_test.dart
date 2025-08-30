// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:synchronous_stream/src/controller.dart';

import 'package:stream_transform/stream_transform.dart';
import 'package:test/test.dart';

void main() {
  group('Scan', () {
    test('produces intermediate values', () async {
      var source = Stream.fromIterable([1, 2, 3, 4]);
      int sum(int x, int y) => x + y;
      var result = await source.scan(0, sum).toList();

      expect(result, [1, 3, 6, 10]);
    });

    test('can create a broadcast stream', () {
      var source = SynchronousDispatchStreamController<int>.broadcast();

      var transformed = source.stream.scan(null, (_, __) {});

      expect(transformed.isBroadcast, true);
    });

    test('forwards errors from source', () async {
      var source = SynchronousDispatchStreamController<int>();

      int sum(int x, int y) => x + y;

      var errors = <Object>[];

      source.stream.scan(0, sum).listen(null, onError: errors.add);

      source.addError(StateError('fail'));
      await Future(() {});

      expect(errors, [isStateError]);
    });

    group('with async combine', () {
      test('returns a Stream of non-futures', () async {
        var source = Stream.fromIterable([1, 2, 3, 4]);
        Future<int> sum(int x, int y) async => x + y;
        var result = await source.scan(0, sum).toList();

        expect(result, [1, 3, 6, 10]);
      });

      test('can return a Stream of futures when specified', () async {
        var source = Stream.fromIterable([1, 2]);
        Future<int> sum(Future<int> x, int y) async => (await x) + y;
        var result = await source.scan<Future<int>>(Future.value(0), sum).toList();

        expect(result, [
          const TypeMatcher<Future<void>>(),
          const TypeMatcher<Future<void>>(),
        ]);
        expect(await result.wait, [1, 3]);
      });

      test('forwards async errors', () async {
        var source = SynchronousDispatchStreamController<int>();

        Future<int> combine(int x, int y) async => throw StateError('fail');

        var errors = <Object>[];

        source.stream.scan(0, combine).listen(null, onError: errors.add);

        source.add(1);
        await Future(() {});

        expect(errors, [isStateError]);
      });
    });
  });
}
