import 'dart:async';

import 'package:meta/meta.dart';
import 'package:synchronous_stream/src/internal.dart';
import 'package:synchronous_stream/src/sink.dart';
import 'package:synchronous_stream/src/stream.dart';
import 'package:synchronous_stream/src/subscription.dart';

/// A high-performance [StreamController] with fast single/broadcast paths,
/// pre-listen event caching (single), and O(1) unsubscription (broadcast).
class SynchronousDispatchStreamController<T> implements StreamController<T> {
  /// Creates a single-subscription controller.
  ///
  /// The controller caches events until the first listener subscribes.
  /// Callbacks mirror [StreamController.onListen], [onPause], [onResume], and [onCancel].
  SynchronousDispatchStreamController({
    this.onListen,
    this.onPause,
    this.onResume,
    this.onCancel,
  }) : isBroadcast = false;

  /// Creates a broadcast controller.
  ///
  /// Broadcast subscriptions support O(1) removal via swap-remove.
  SynchronousDispatchStreamController.broadcast({this.onListen, this.onCancel})
      : isBroadcast = true;

  /// Whether this controller operates in broadcast mode.
  final bool isBroadcast;

  @override
  void Function()? onListen;

  @override
  void Function()? onPause;

  @override
  void Function()? onResume;

  @override
  FutureOr<void> Function()? onCancel;

  late final Stream<T> _stream = NotifierStream<T>(this);
  late final StreamSink<T> _sink = ControllerSink<T>(this);

  /// The stream that consumers listen to.
  @override
  Stream<T> get stream => _stream;

  /// The sink used to add events, errors, and to close the controller.
  @override
  StreamSink<T> get sink => _sink;

  NotifierStreamSubscription<T>? _singleSubscription;
  final List<NotifierStreamSubscription<T>> _broadcastSubscriptions =
      <NotifierStreamSubscription<T>>[];

  bool _isClosed = false;
  int _notificationDepth = 0;
  bool _needsSweepAfterNotify = false;
  int _pendingAddStreamsCount = 0;
  final Completer<void> _doneCompleter = Completer<void>();

  List<Object?>? _preListenQueue;
  List<Object?> get __preListenQueue => _preListenQueue ??= <Object?>[];

  /// Whether [close] has been called.
  @override
  bool get isClosed => _isClosed;

  /// Whether the stream has any listeners.
  @override
  bool get hasListener => isBroadcast
      ? _broadcastSubscriptions.isNotEmpty
      : _singleSubscription != null;

  /// Whether the single-subscription stream is currently paused.
  ///
  /// Always `false` for broadcast streams.
  @override
  bool get isPaused {
    if (isBroadcast) return false;
    final subscription = _singleSubscription;
    return subscription != null && subscription.pauseCount > 0;
  }

  /// Completes when the controller is closed and all pending [addStream]s finish.
  @override
  Future<void> get done => _doneCompleter.future;

  /// Adds a data event to the controller.
  ///
  /// Throws [StateError] if the controller is already closed.
  @pragma('vm:prefer-inline')
  @override
  void add(T event) {
    if (_isClosed) {
      throw StateError('Cannot add event after closing');
    }

    if (isBroadcast) {
      if (_broadcastSubscriptions.isNotEmpty) {
        _notifyDataBroadcast(event);
      }
      return;
    }

    if (_singleSubscription == null) {
      __preListenQueue
        ..add(tagData)
        ..add(event);
      return;
    }

    _singleSubscription!.handleDataFast(event);
  }

  /// Adds an error event to the controller.
  ///
  /// Throws [StateError] if the controller is already closed.
  @pragma('vm:prefer-inline')
  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    if (_isClosed) {
      throw StateError('Cannot add error after closing');
    }

    if (isBroadcast) {
      if (_broadcastSubscriptions.isNotEmpty) {
        _notifyErrorBroadcast(error, stackTrace);
      }
      return;
    }

    if (_singleSubscription == null) {
      __preListenQueue
        ..add(tagError)
        ..add(error);
      return;
    }

    _singleSubscription!.handleErrorSingle(error, stackTrace);
  }

  /// Pipes all events from [source] into this controller.
  ///
  /// Respects [cancelOnError] per the [StreamController.addStream] contract.
  @override
  Future<void> addStream(Stream<T> source, {bool? cancelOnError}) async {
    if (_isClosed) throw StateError('Cannot addStream after closing');

    _pendingAddStreamsCount++;
    final bool cancelUpstreamOnError = cancelOnError ?? false;
    final Completer<void> finishCompleter = Completer<void>();

    late final StreamSubscription<T> upstreamSubscription;
    upstreamSubscription = source.listen(
      (value) => add(value),
      onError: (Object error, StackTrace stackTrace) {
        addError(error, stackTrace);
        if (cancelUpstreamOnError && !finishCompleter.isCompleted) {
          finishCompleter.complete();
        }
      },
      onDone: () {
        if (!finishCompleter.isCompleted) finishCompleter.complete();
      },
      cancelOnError: cancelUpstreamOnError,
    );

    try {
      await finishCompleter.future;
    } finally {
      upstreamSubscription.cancel().ignore();
      _pendingAddStreamsCount--;
      _maybeCompleteDone();
    }
  }

  /// Closes the controller and eventually completes [done].
  ///
  /// In single mode, a pending listener will receive buffered events and `done`.
  /// In broadcast mode, all listeners receive `done`.
  @override
  Future<void> close() {
    if (_isClosed) return _doneCompleter.future;
    _isClosed = true;

    if (isBroadcast) {
      if (_broadcastSubscriptions.isNotEmpty) _notifyDoneBroadcast();
    } else {
      if (_singleSubscription != null) {
        _singleSubscription!.handleDoneFast();
      } else {
        __preListenQueue.add(tagDone);
      }
    }

    _maybeCompleteDone();
    return _doneCompleter.future;
  }

  @pragma('vm:prefer-inline')
  @internal
  NotifierStreamSubscription<T> addSubscription({
    DataHandler<T>? onData,
    ErrorHandler? onError,
    DoneHandler? onDone,
    bool? cancelOnError,
  }) {
    final bool cancelThisOnError = cancelOnError ?? false;

    if (!isBroadcast) {
      if (_singleSubscription != null) {
        throw StateError('Single-subscription stream already has a listener');
      }

      final NotifierStreamSubscription<T> subscription =
          NotifierStreamSubscription<T>(
        controller: this,
        cancelOnError: cancelThisOnError,
        isBroadcast: false,
        onData: onData,
        onError: onError,
        onDone: onDone,
      );

      _singleSubscription = subscription;

      onListen?.call();

      if (_preListenQueue != null && _preListenQueue!.isNotEmpty) {
        final List<Object?> detachedQueue = _preListenQueue!;
        _preListenQueue = null;
        subscription.drainSingleTaggedQueue(detachedQueue);
      }

      if (_isClosed && !subscription.isCanceled) {
        subscription.handleDoneFast();
      }

      return subscription;
    }

    final bool hadNoListeners = _broadcastSubscriptions.isEmpty;

    final NotifierStreamSubscription<T> subscription =
        NotifierStreamSubscription<T>(
      controller: this,
      cancelOnError: cancelThisOnError,
      isBroadcast: true,
      onData: onData,
      onError: onError,
      onDone: onDone,
    );

    subscription.broadcastIndex = _broadcastSubscriptions.length;
    _broadcastSubscriptions.add(subscription);

    if (hadNoListeners) onListen?.call();

    if (_isClosed && !subscription.isCanceled) {
      subscription.handleDoneFast();
    }

    return subscription;
  }

  @internal
  FutureOr<void>? removeSubscription(
    NotifierStreamSubscription<T> subscription,
  ) {
    if (!isBroadcast) {
      if (!identical(_singleSubscription, subscription)) return null;
      _singleSubscription = null;
      final FutureOr<void>? onCancelResult = onCancel?.call();
      _maybeCompleteDone();
      return onCancelResult;
    }

    if (_notificationDepth > 0) {
      subscription.isCanceled = true;
      _needsSweepAfterNotify = true;
      return null;
    }

    final int index = subscription.broadcastIndex;
    if (index >= 0 &&
        index < _broadcastSubscriptions.length &&
        identical(_broadcastSubscriptions[index], subscription)) {
      final NotifierStreamSubscription<T> last =
          _broadcastSubscriptions.removeLast();
      if (!identical(last, subscription)) {
        _broadcastSubscriptions[index] = last;
        last.broadcastIndex = index;
      }
      subscription.broadcastIndex = -1;

      if (_broadcastSubscriptions.isEmpty) {
        final FutureOr<void>? onCancelResult = onCancel?.call();
        _maybeCompleteDone();
        return onCancelResult;
      }
    }
    return null;
  }

  @pragma('vm:prefer-inline')
  void _beginNotify() => _notificationDepth++;

  @pragma('vm:prefer-inline')
  void _endNotify() {
    _notificationDepth--;
    if (_notificationDepth == 0 && _needsSweepAfterNotify) {
      _needsSweepAfterNotify = false;

      int index = 0;
      while (index < _broadcastSubscriptions.length) {
        final NotifierStreamSubscription<T> subscription =
            _broadcastSubscriptions[index];
        if (subscription.isCanceled) {
          final NotifierStreamSubscription<T> last =
              _broadcastSubscriptions.removeLast();
          if (!identical(last, subscription)) {
            _broadcastSubscriptions[index] = last;
            last.broadcastIndex = index;
            continue;
          }
        } else {
          index++;
        }
      }

      if (_broadcastSubscriptions.isEmpty) {
        onCancel?.call();
        _maybeCompleteDone();
      }
    }
  }

  @pragma('vm:prefer-inline')
  void _notifyDataBroadcast(T event) {
    _beginNotify();
    final int length = _broadcastSubscriptions.length;
    for (var index = 0; index < length; index++) {
      final subscription = _broadcastSubscriptions[index];
      if (!subscription.isCanceled) {
        subscription.deliverDataBroadcast(event);
      }
    }
    _endNotify();
  }

  @pragma('vm:prefer-inline')
  void _notifyErrorBroadcast(Object error, StackTrace? maybeStack) {
    _beginNotify();

    StackTrace? cachedStackTrace;
    StackTrace ensureStack() =>
        cachedStackTrace ??= maybeStack ?? StackTrace.current;

    final int length = _broadcastSubscriptions.length;
    for (var index = 0; index < length; index++) {
      final subscription = _broadcastSubscriptions[index];
      if (subscription.isCanceled) continue;

      if (subscription.onErrorCallback != null) {
        subscription.deliverErrorBroadcast(error, ensureStack());
      } else {
        subscription.reportUnhandled(error, ensureStack());
      }
    }

    _endNotify();
  }

  @pragma('vm:prefer-inline')
  void _notifyDoneBroadcast() {
    _beginNotify();
    final int length = _broadcastSubscriptions.length;
    for (var index = 0; index < length; index++) {
      final subscription = _broadcastSubscriptions[index];
      if (!subscription.isCanceled) {
        subscription.deliverDoneBroadcast();
      }
    }
    _endNotify();
  }

  @pragma('vm:prefer-inline')
  void _maybeCompleteDone() {
    if (_isClosed &&
        _pendingAddStreamsCount == 0 &&
        !_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
  }
}
