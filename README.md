# SynchronousDispatchStreamController

Synchronous notifier that implements `StreamController` variant with O(1) broadcast unsubscription (swap-remove) and compact tagged queues (pre-listen/pause) with lazy stack-trace capture and allocation-lean hot paths

- **O(1) broadcast unsubscription (swap-remove)** with a deferred sweep that avoids modifying the subscriber list mid-notification
- **Compact tagged queues** for pre-listen and paused delivery (`[tag, payload?]`) to reduce allocations and branch costs
- **Lazy stack-trace capture for errors** - a `StackTrace` is produced only if at least one listener requests it
- **Allocation-lean hot paths** for data/error/done to minimize overhead in tight event loops

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
  final controller = SynchronousDispatchStreamController<int>(
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
