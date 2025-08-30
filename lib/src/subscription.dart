import 'dart:async';

import 'package:meta/meta.dart';
import 'package:synchronous_stream/src/implementation.dart';
import 'package:synchronous_stream/src/internal.dart';

@internal
class NotifierStreamSubscription<T> implements StreamSubscription<T> {
  NotifierStreamSubscription({
    required this.controller,
    required this.cancelOnError,
    required this.isBroadcast,
    DataHandler<T>? onData,
    ErrorHandler? onError,
    DoneHandler? onDone,
  })  : _onData = onData,
        onErrorCallback = onError,
        _onDone = onDone;

  final SynchronousDispatchStreamControllerImpl<T> controller;
  final bool cancelOnError;
  final bool isBroadcast;

  DataHandler<T>? _onData;
  ErrorHandler? onErrorCallback;
  DoneHandler? _onDone;

  int pauseCount = 0;
  bool isCanceled = false;
  bool isDoneSent = false;

  int broadcastIndex = -1;

  List<Object?>? _singleTaggedQueue;
  List<Object?> get __singleTaggedQueue => _singleTaggedQueue ??= <Object?>[];

  @override
  Future<void> cancel() {
    if (isCanceled) return Future.value();
    isCanceled = true;
    final FutureOr<void>? removeResult = controller.removeSubscription(this);
    if (removeResult is Future<void>) return removeResult;
    return Future.value();
  }

  @override
  bool get isPaused => pauseCount > 0;

  @override
  void onData(void Function(T data)? handleData) => _onData = handleData;

  @override
  void onError(Function? handleError) => onErrorCallback = switch (handleError) {
        void Function(Object, StackTrace) _ => handleError,
        void Function(Object) _ => (error, _) => handleError(error),
        null => null,
        _ => throw ArgumentError.value(
            handleError,
            'onError',
            'Must be void Function(Object) or void Function(Object, StackTrace)',
          ),
      };

  @override
  void onDone(void Function()? handleDone) => _onDone = handleDone;

  @override
  void pause([Future<void>? resumeSignal]) {
    if (isBroadcast) return;
    pauseCount++;
    controller.onPause?.call();
    resumeSignal?.whenComplete(resume);
  }

  @override
  void resume() {
    if (isBroadcast || pauseCount == 0) return;

    pauseCount--;
    if (pauseCount == 0) {
      controller.onResume?.call();

      if (_singleTaggedQueue != null && _singleTaggedQueue!.isNotEmpty && !isCanceled) {
        final List<Object?> detachedQueue = _singleTaggedQueue!;
        _singleTaggedQueue = null;
        drainSingleTaggedQueue(detachedQueue);
      }
    }
  }

  @override
  Future<E> asFuture<E>([E? futureValue]) {
    final Completer<E> completer = Completer<E>();

    onDone(() {
      if (!isCanceled && !completer.isCompleted) {
        completer.complete(futureValue as E);
      }
    });

    onError((Object error, StackTrace stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
      if (!isBroadcast && cancelOnError) {
        cancel().ignore();
      }
    });

    return completer.future;
  }

  @pragma('vm:prefer-inline')
  void handleDataFast(T data) {
    if (isCanceled || isDoneSent) return;

    if (!isBroadcast && pauseCount > 0) {
      __singleTaggedQueue
        ..add(tagData)
        ..add(data);
      return;
    }

    final DataHandler<T>? onDataHandler = _onData;
    if (onDataHandler == null) return;

    try {
      onDataHandler(data);
    } catch (error, stackTrace) {
      reportUnhandled(error, stackTrace);
    }
  }

  @pragma('vm:prefer-inline')
  void handleErrorSingle(Object error, StackTrace? maybeStackTrace) {
    if (isCanceled || isDoneSent) return;

    if (!isBroadcast && pauseCount > 0) {
      __singleTaggedQueue
        ..add(tagError)
        ..add(error);
      return;
    }

    if (onErrorCallback != null) {
      final StackTrace stackTrace = maybeStackTrace ?? StackTrace.current;
      try {
        onErrorCallback!(error, stackTrace);
      } catch (handlerError, handlerStack) {
        reportUnhandled(handlerError, handlerStack);
      }
      if (cancelOnError) {
        cancel().ignore();
      }
      return;
    }

    reportUnhandled(error, maybeStackTrace ?? StackTrace.current);
  }

  @pragma('vm:prefer-inline')
  void handleDoneFast() {
    if (isCanceled || isDoneSent) return;

    if (!isBroadcast && pauseCount > 0) {
      __singleTaggedQueue.add(tagDone);
      return;
    }

    isDoneSent = true;

    final DoneHandler? onDoneHandler = _onDone;
    if (onDoneHandler == null) return;

    try {
      onDoneHandler();
    } catch (error, stackTrace) {
      reportUnhandled(error, stackTrace);
    }
  }

  @pragma('vm:prefer-inline')
  void deliverDataBroadcast(T data) {
    if (isCanceled || isDoneSent) return;

    final DataHandler<T>? onDataHandler = _onData;
    if (onDataHandler == null) return;

    try {
      onDataHandler(data);
    } catch (error, stackTrace) {
      reportUnhandled(error, stackTrace);
    }
  }

  @pragma('vm:prefer-inline')
  void deliverErrorBroadcast(Object error, StackTrace stackTrace) {
    if (isCanceled || isDoneSent) return;

    if (onErrorCallback != null) {
      try {
        onErrorCallback!(error, stackTrace);
      } catch (handlerError, handlerStack) {
        reportUnhandled(handlerError, handlerStack);
      }
      if (cancelOnError) {
        cancel();
      }
    } else {
      reportUnhandled(error, stackTrace);
    }
  }

  @pragma('vm:prefer-inline')
  void deliverDoneBroadcast() {
    if (isCanceled || isDoneSent) return;

    isDoneSent = true;

    final DoneHandler? onDoneHandler = _onDone;
    if (onDoneHandler == null) return;

    try {
      onDoneHandler();
    } catch (error, stackTrace) {
      reportUnhandled(error, stackTrace);
    }
  }

  void drainSingleTaggedQueue(List<Object?> taggedQueue) {
    var cursor = 0;
    while (cursor < taggedQueue.length && !isCanceled) {
      final int tag = taggedQueue[cursor++]! as int;
      final _ = switch (tag) {
        tagData => handleDataFast(taggedQueue[cursor++] as T),
        tagError => handleErrorSingle(taggedQueue[cursor++]!, null),
        _ => handleDoneFast(),
      };
    }
  }

  @pragma('vm:never-inline')
  void reportUnhandled(Object error, StackTrace stackTrace) {
    Zone.current.handleUncaughtError(error, stackTrace);
  }
}
