# SynchronousDispatchStreamController

High-performance drop-in replacement for `StreamController` with optimized single-subscription and broadcast modes.

- **Pre-listen buffering (single)** — events are cached until the first listener subscribes.
- **O(1) broadcast unsubscription** — swap-remove keeps the subscriber list dense.
- **Per-subscription `cancelOnError`** — each listener can decide independently.
- **Unified error handler** — accepts either `(Object)` or `(Object, StackTrace)`.


## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  synchronous_stream: ^1.0.0
```

> Import:
> ```dart
> import 'package:synchronous_stream/synchronous_stream.dart';
> ```

## Quick Start
```dart
import 'dart:async';
import 'package:notifier_stream_controller2/notifier_stream_controller2.dart';

Future<void> main() async {
  final controller = NotifierStreamController2<int>(
    onListen: () => print('onListen'),
    onPause: () => print('onPause'),
    onResume: () => print('onResume'),
    onCancel: () => print('onCancel'),
  );

  // Pre-listen buffering (single)
  controller.add(1);
  controller.add(2);

  final sub = controller.stream.listen(
    (v) => print('data: $v'),
    onError: (e, st) => print('error: $e'),
    onDone: () => print('done'),
  );

  sub.pause(Future<void>.delayed(const Duration(milliseconds: 20)));
  controller.add(3);

  await controller.close();
  await controller.done;
}
```
