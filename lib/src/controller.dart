import 'dart:async';

import 'package:synchronous_stream/src/internal.dart';
import 'package:synchronous_stream/src/implementation.dart';

/// A high-performance [StreamController] with fast single/broadcast paths,
/// pre-listen event caching (single), and O(1) unsubscription (broadcast).
abstract interface class SynchronousDispatchStreamController<T> implements StreamController<T> {
  /// Creates a single-subscription controller.
  ///
  /// The controller caches events until the first listener subscribes.
  /// Callbacks mirror [StreamController.onListen], [onPause], [onResume], and [onCancel].
  factory SynchronousDispatchStreamController({
    VoidCallback<void>? onListen,
    VoidCallback<void>? onPause,
    VoidCallback<void>? onResume,
    VoidCallback<FutureOr<void>>? onCancel,
  }) =>
      SynchronousDispatchStreamControllerImpl(
        onListen: onListen,
        onPause: onPause,
        onResume: onResume,
        onCancel: onCancel,
      );

  /// Creates a broadcast controller.
  ///
  /// Broadcast subscriptions support O(1) removal via swap-remove.
  factory SynchronousDispatchStreamController.broadcast({
    VoidCallback<void>? onListen,
    VoidCallback<FutureOr<void>>? onCancel,
  }) =>
      SynchronousDispatchStreamControllerImpl.broadcast(
        onListen: onListen,
        onCancel: onCancel,
      );

  /// Whether this controller operates in broadcast mode.
  bool get isBroadcast;

  @override
  void Function()? get onListen;

  @override
  void Function()? get onPause;

  @override
  void Function()? get onResume;

  @override
  FutureOr<void> Function()? get onCancel;

  /// The stream that consumers listen to.
  @override
  Stream<T> get stream;

  /// The sink used to add events, errors, and to close the controller.
  @override
  StreamSink<T> get sink;
}
