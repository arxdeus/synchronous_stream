import 'dart:async';
import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:synchronous_stream/synchronous_stream.dart';

const int kEvents = 1000000; // events per run() call
const int kSubscribers = 16; // listeners in broadcast scenarios

/// Factory that returns either single or broadcast controller.
typedef IntControllerFactory = StreamController<int> Function({required bool broadcast});

/// A named implementation (label + factory). Add any number of implementations here.
class Impl {
  final String name;
  final IntControllerFactory factory;
  const Impl(this.name, this.factory);
}

/// Implementations under test.
/// - std: Dart's StreamController (sync:true)
/// - notifier: SynchronousDispatchStreamController
final List<Impl> impls = [
  Impl(
      'std(sync)',
      ({required bool broadcast}) => broadcast
          ? StreamController<int>.broadcast(sync: true)
          : StreamController<int>(sync: true)),
  Impl(
      'notifier',
      ({required bool broadcast}) => broadcast
          ? SynchronousDispatchStreamController<int>.broadcast()
          : SynchronousDispatchStreamController<int>()),
];

void main() {
  final benches = <BenchmarkBase>[
    for (final impl in impls) _SingleAddHot(impl),
    for (final impl in impls) _SinglePrelistenAdd(impl),
    for (final impl in impls) _SinglePauseAdd(impl),
    for (final impl in impls) _BroadcastAddHot(impl),
    for (final impl in impls) _BroadcastMassCancel(impl),
    for (final impl in impls) _ErrorsUnary(impl),
    for (final impl in impls) _ErrorsBinary(impl),
  ];

  for (final b in benches) {
    b.report();
  }
}

class CustomPrintEmitter extends ScoreEmitter {
  void emit(String testName, double value) {
    final ms = value / 1000;
    print('$testName: $ms ms.');
  }
}

/// Base class for controller benchmarks bound to a specific implementation.
abstract class _ControllerBench extends BenchmarkBase {
  final Impl impl;
  int _runs = 0; // how many times run() was invoked by harness

  _ControllerBench(String scenario, this.impl)
      : super('$scenario/${impl.name}', emitter: CustomPrintEmitter());

  /// Helper to track harness run-count for assertions.
  void countRun() => _runs++;
  int get runs => _runs;
}

/// ------------- Scenarios (identical across controllers) -------------

/// Single: hot add with active listener.
class _SingleAddHot extends _ControllerBench {
  _SingleAddHot(Impl impl) : super('single:add_hot', impl);

  late StreamController<int> ctrl;
  int sum = 0;

  @override
  void setup() {
    ctrl = impl.factory(broadcast: false);
    sum = 0;
    runs == 0; // touch to avoid DCE (no-op)
    ctrl.stream.listen((v) => sum += v, onError: (_, __) {});
  }

  @override
  void run() {
    for (var i = 0; i < kEvents; i++) {
      ctrl.add(1);
    }
    countRun();
  }

  @override
  void teardown() {
    final expected = kEvents * runs;
    if (sum != expected) {
      throw StateError('[${impl.name}] single:add_hot mismatch: $sum != $expected');
    }
    ctrl.close();
  }
}

/// Single: cost of adding into pre-listen buffer (no listener during run()).
/// Validation is not asserted here to keep behavior identical across impls
/// (some std drains might involve microtasks).
class _SinglePrelistenAdd extends _ControllerBench {
  _SinglePrelistenAdd(Impl impl) : super('single:prelisten_add', impl);

  late StreamController<int> ctrl;
  int sum = 0;

  @override
  void setup() {
    ctrl = impl.factory(broadcast: false);
    sum = 0;
  }

  @override
  void run() {
    for (var i = 0; i < kEvents; i++) {
      ctrl.add(1);
    }
    countRun();
  }

  @override
  void teardown() {
    // Drain after measurement (not asserted to stay impl-agnostic).
    final sub = ctrl.stream.listen((v) => sum += v);
    sub.cancel();
    ctrl.close();
  }
}

/// Single: add while paused (measures queuing cost). No strict assertion
/// to remain compatible with controllers that flush in microtasks.
class _SinglePauseAdd extends _ControllerBench {
  _SinglePauseAdd(Impl impl) : super('single:pause_add', impl);

  late StreamController<int> ctrl;
  late StreamSubscription<int> sub;
  int sum = 0;

  @override
  void setup() {
    ctrl = impl.factory(broadcast: false);
    sum = 0;
    sub = ctrl.stream.listen((v) => sum += v);
    sub.pause();
  }

  @override
  void run() {
    for (var i = 0; i < kEvents; i++) {
      ctrl.add(1);
    }
    countRun();
  }

  @override
  void teardown() {
    sub.resume(); // flush after measurement
    sub.cancel();
    ctrl.close();
  }
}

/// Broadcast: hot add to N listeners; verification is synchronous for both impls.
class _BroadcastAddHot extends _ControllerBench {
  _BroadcastAddHot(Impl impl) : super('broadcast:add_hot', impl);

  late StreamController<int> ctrl;
  late List<int> counts;
  late List<StreamSubscription<int>> subs;

  @override
  void setup() {
    ctrl = impl.factory(broadcast: true);
    counts = List<int>.filled(kSubscribers, 0);
    subs = <StreamSubscription<int>>[];
    for (var i = 0; i < kSubscribers; i++) {
      subs.add(ctrl.stream.listen((_) => counts[i]++));
    }
  }

  @override
  void run() {
    for (var i = 0; i < kEvents; i++) {
      ctrl.add(1);
    }
    countRun();
  }

  @override
  void teardown() {
    final expected = kEvents * runs;
    for (var i = 0; i < kSubscribers; i++) {
      if (counts[i] != expected) {
        throw StateError('[${impl.name}] broadcast:add_hot[$i] ${counts[i]} != $expected');
      }
    }
    for (final s in subs) {
      s.cancel();
    }
    ctrl.close();
  }
}

/// Broadcast: mass-cancel; per-run we create a fresh batch and cancel it,
/// so the scenario focuses on cancellation cost and stays stable across runs.
class _BroadcastMassCancel extends _ControllerBench {
  _BroadcastMassCancel(Impl impl) : super('broadcast:mass_cancel', impl);

  late StreamController<int> ctrl;

  @override
  void setup() {
    ctrl = impl.factory(broadcast: true);
  }

  @override
  void run() {
    final subs = <StreamSubscription<int>>[];
    for (var i = 0; i < kSubscribers; i++) {
      subs.add(ctrl.stream.listen((_) {}));
    }
    for (final s in subs) {
      s.cancel();
    }
    countRun();
  }

  @override
  void teardown() {
    ctrl.close();
  }
}

/// Errors: unary onError(Object)
class _ErrorsUnary extends _ControllerBench {
  _ErrorsUnary(Impl impl) : super('errors:unary', impl);

  late StreamController<int> ctrl;
  int errors = 0;

  @override
  void setup() {
    ctrl = impl.factory(broadcast: false);
    errors = 0;
    ctrl.stream.listen((_) {}, onError: (Object e) => errors++);
  }

  @override
  void run() {
    for (var i = 0; i < kEvents; i++) {
      ctrl.addError('e$i');
    }
    countRun();
  }

  @override
  void teardown() {
    final expected = kEvents * runs;
    if (errors != expected) {
      throw StateError('[${impl.name}] errors:unary $errors != $expected');
    }
    ctrl.close();
  }
}

/// Errors: binary onError(Object, StackTrace)
class _ErrorsBinary extends _ControllerBench {
  _ErrorsBinary(Impl impl) : super('errors:binary', impl);

  late StreamController<int> ctrl;
  int errors = 0;

  @override
  void setup() {
    ctrl = impl.factory(broadcast: false);
    errors = 0;
    ctrl.stream.listen((_) {}, onError: (Object e, StackTrace st) => errors++);
  }

  @override
  void run() {
    for (var i = 0; i < kEvents; i++) {
      ctrl.addError('e$i');
    }
    countRun();
  }

  @override
  void teardown() {
    final expected = kEvents * runs;
    if (errors != expected) {
      throw StateError('[${impl.name}] errors:binary $errors != $expected');
    }
    ctrl.close();
  }
}
