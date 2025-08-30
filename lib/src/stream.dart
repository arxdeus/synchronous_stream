import 'dart:async';

import 'package:synchronous_stream/src/implementation.dart';
import 'package:synchronous_stream/src/internal.dart';

class NotifierStream<T> extends Stream<T> {
  NotifierStream(this.controller);

  final SynchronousDispatchStreamControllerImpl<T> controller;

  @override
  bool get isBroadcast => controller.isBroadcast;

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final ErrorHandler? unifiedErrorHandler = switch (onError) {
      void Function(Object) _ => (error, _) => onError(error),
      void Function(Object, StackTrace) _ => onError,
      null => null,
      _ => throw ArgumentError.value(
          onError,
          'onError',
          'Must be void Function(Object) or void Function(Object, StackTrace)',
        ),
    };

    return controller.addSubscription(
      onData: onData,
      onError: unifiedErrorHandler,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}
