// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:synchronous_stream/src/controller.dart';

StreamController<T> createController<T>(String streamType) {
  switch (streamType) {
    case 'single subscription':
      return SynchronousDispatchStreamController<T>();
    case 'broadcast':
      return SynchronousDispatchStreamController<T>.broadcast();
    default:
      throw ArgumentError.value(streamType, 'streamType', 'Must be one of $streamTypes');
  }
}

const streamTypes = ['single subscription', 'broadcast'];
