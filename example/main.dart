import 'dart:async';

import 'package:synchronous_stream/synchronous_stream.dart';

Future<void> main() async {
  final b = SynchronousDispatchStreamController<int>.broadcast();

  final a = b.stream.listen((v) => print('[A] $v'));
  final _ = b.stream.listen(
    (v) => print('[S] $v'),
    onError: (e) => print('[S] error: $e'),
    cancelOnError: true,
  );

  b.add(10);
  b.addError('boom'); // `s` is removed in O(1); `a` keeps receiving events.
  b.add(11);

  await a.cancel();
  await b.close();
  await b.done;
}
