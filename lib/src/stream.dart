import 'dart:async';

import 'package:synchronous_stream/src/controller.dart';
import 'package:synchronous_stream/src/internal.dart';

class NotifierStream<T> extends Stream<T> {
  NotifierStream(this.controller);

  final SynchronousDispatchStreamController<T> controller;

  @override
  bool get isBroadcast => controller.isBroadcast;

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    ErrorHandler? unifiedErrorHandler;

    if (onError != null) {
      if (onError is void Function(Object)) {
        final void Function(Object) unary = onError;
        unifiedErrorHandler = (Object error, StackTrace _) => unary(error);
      } else if (onError is void Function(Object, StackTrace)) {
        unifiedErrorHandler = onError;
      } else {
        throw ArgumentError.value(
          onError,
          'onError',
          'Must be void Function(Object) or void Function(Object, StackTrace)',
        );
      }
    }

    return controller.addSubscription(
      onData: onData,
      onError: unifiedErrorHandler,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}
