import 'dart:async';

import 'package:synchronous_stream/synchronous_stream.dart';

Future<void> main() async {
  // -----------------------------
  // Single-subscription example
  // -----------------------------
  final single = SynchronousDispatchStreamController<int>(
    onListen: () => print('[single] onListen'),
    onPause: () => print('[single] onPause'),
    onResume: () => print('[single] onResume'),
    onCancel: () => print('[single] onCancel'),
  );

  // Pre-listen buffering: these will be delivered after listen()
  single.add(1);
  single.add(2);

  final sub = single.stream.listen(
    (v) => print('[single] data: $v'),
    // Both shapes are accepted; here we use the (Object, StackTrace) form.
    onError: (Object e, StackTrace st) => print('[single] error: $e'),
    onDone: () => print('[single] done'),
  );

  // Pause while adding new events; they queue and flush on resume.
  sub.pause(Future<void>.delayed(const Duration(milliseconds: 20)));
  single.add(3);

  // Pipe from another stream; done will wait for this to finish.
  final src =
      Stream<int>.periodic(const Duration(milliseconds: 10), (i) => i).take(3);
  await single.addStream(src);

  await single.close();
  await single.done;

  // -----------------------------
  // Broadcast example
  // -----------------------------
  final broadcast = SynchronousDispatchStreamController<int>.broadcast(
    onListen: () => print('[broadcast] onListen'),
    onCancel: () => print('[broadcast] onCancel'),
  );

  final a = broadcast.stream.listen(
    (v) => print('[A] data: $v'),
    onDone: () => print('[A] done'),
  );

  final _ = broadcast.stream.listen(
    (v) => print('[B] data: $v'),
    // Using the unary onError form here; will be normalized internally.
    onError: (Object e) => print('[B] error: $e'),
    cancelOnError: true, // only this subscription cancels on its own error
  );

  broadcast.add(10);
  broadcast.addError('oops'); // cancels B only
  broadcast.add(11); // delivered to A (B already canceled)

  await a.cancel(); // last listener removed -> onCancel fires
  await broadcast.close();
  await broadcast.done;

  print('Example finished.');
}
