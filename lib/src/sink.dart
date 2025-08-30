import 'dart:async';

import 'package:meta/meta.dart';
import 'package:synchronous_stream/src/controller.dart';

@internal
class ControllerSink<T> implements StreamSink<T> {
  ControllerSink(this.controller);

  final SynchronousDispatchStreamController<T> controller;

  @pragma('vm:prefer-inline')
  @override
  void add(T data) => controller.add(data);

  @pragma('vm:prefer-inline')
  @override
  void addError(Object error, [StackTrace? stackTrace]) => controller.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<T> stream) => controller.addStream(stream);

  @override
  Future<void> close() => controller.close();

  @override
  Future<void> get done => controller.done;
}
