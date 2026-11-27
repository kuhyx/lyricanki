import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyricanki/services/sync_scheduler.dart';

/// A timer the test fires by hand, so nothing here waits on a real clock.
class _ManualTimer implements Timer {
  _ManualTimer(this.delay, this._callback);

  final Duration delay;
  final void Function() _callback;
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  @override
  void cancel() => _active = false;

  void fire() {
    if (!_active) return;
    _active = false;
    _callback();
  }
}

const _debounce = Duration(seconds: 2);
const _retry = Duration(seconds: 30);
const _maxRetry = Duration(seconds: 60);

void main() {
  late List<_ManualTimer> timers;
  late List<SyncOutcome> script;
  late int calls;
  late SyncScheduler scheduler;

  Timer newTimer(Duration delay, void Function() callback) {
    final timer = _ManualTimer(delay, callback);
    timers.add(timer);
    return timer;
  }

  SyncScheduler make(SyncTick tick) => SyncScheduler(
    tick,
    debounce: _debounce,
    firstRetry: _retry,
    maxRetry: _maxRetry,
    timer: newTimer,
  );

  Future<SyncOutcome> scripted() async {
    calls++;
    return script.isEmpty ? SyncOutcome.synced : script.removeAt(0);
  }

  List<_ManualTimer> active() => timers.where((t) => t.isActive).toList();

  /// Fires the one armed timer and lets the sync it starts finish.
  Future<void> fireOnly(Duration expected) async {
    final armed = active();
    expect(armed, hasLength(1));
    expect(armed.single.delay, expected);
    armed.single.fire();
    await pumpEventQueue();
  }

  setUp(() {
    timers = <_ManualTimer>[];
    script = <SyncOutcome>[];
    calls = 0;
    scheduler = make(scripted);
  });
  tearDown(() => scheduler.dispose());

  test('a burst of writes syncs once, after the debounce', () async {
    scheduler
      ..soon()
      ..soon()
      ..soon();
    expect(calls, 0, reason: 'never on the write path itself');
    await fireOnly(_debounce);
    expect(calls, 1);
  });

  test('a failed sync retries by itself with a growing delay', () async {
    script = <SyncOutcome>[
      SyncOutcome.failed,
      SyncOutcome.failed,
      SyncOutcome.failed,
    ];
    await scheduler.run();
    expect(calls, 1);
    await fireOnly(_retry);
    expect(calls, 2, reason: 'retried with no tap');
    await fireOnly(_retry * 2);
    expect(calls, 3);
    await fireOnly(_maxRetry);
    expect(calls, 4, reason: 'backoff is capped, retries go on');
    expect(active(), isEmpty, reason: 'a success arms no retry');

    script = <SyncOutcome>[SyncOutcome.failed];
    await scheduler.run();
    await fireOnly(_retry);
    expect(calls, 6, reason: 'success reset the backoff');
  });

  test('a lock or a missing sign-in waits for the user, not a timer', () async {
    script = <SyncOutcome>[SyncOutcome.locked, SyncOutcome.notSetUp];
    await scheduler.run();
    await scheduler.run();
    expect(calls, 2);
    expect(active(), isEmpty);
  });

  test('a new sync replaces a pending retry', () async {
    script = <SyncOutcome>[SyncOutcome.failed];
    await scheduler.run();
    final retry = active().single;
    await scheduler.run();
    expect(retry.isActive, isFalse);
    expect(calls, 2);
  });

  test('never overlaps; requests during a sync collapse into one', () async {
    final gate = Completer<void>();
    var running = 0;
    var peak = 0;
    scheduler = make(() async {
      calls++;
      running++;
      if (running > peak) peak = running;
      if (calls == 1) await gate.future;
      running--;
      return SyncOutcome.synced;
    });

    final first = scheduler.run();
    unawaited(scheduler.run());
    unawaited(scheduler.run());
    gate.complete();
    await first;
    expect(calls, 2);
    expect(peak, 1);
  });

  test('a write that lands mid-sync is pushed by a follow-up sync', () async {
    final gate = Completer<void>();
    scheduler = make(() async {
      if (++calls == 1) await gate.future;
      return SyncOutcome.synced;
    });

    final first = scheduler.run();
    scheduler.soon();
    active().single.fire();
    gate.complete();
    await first;
    expect(calls, 2);
  });

  test('flush runs a pending debounce now, and is a no-op without one', () {
    scheduler.flush();
    expect(calls, 0);
    scheduler
      ..soon()
      ..flush();
    expect(calls, 1, reason: 'the app may be killed before the timer fires');
    expect(active(), isEmpty);
  });

  test('run takes a one-off tick, e.g. the manual button', () async {
    var manual = 0;
    await scheduler.run(() async {
      manual++;
      return SyncOutcome.failed;
    });
    expect(manual, 1);
    await fireOnly(_retry);
    expect(calls, 1, reason: 'the retry uses the background tick');
  });

  test('dispose cancels every timer and later requests', () async {
    script = <SyncOutcome>[SyncOutcome.failed];
    await scheduler.run();
    scheduler
      ..soon()
      ..dispose();
    expect(active(), isEmpty);
    await scheduler.run();
    scheduler.soon();
    expect(calls, 1);
    expect(active(), isEmpty);
  });

  test('stops after a tick that outlives dispose', () async {
    final gate = Completer<void>();
    scheduler = make(() async {
      calls++;
      await gate.future;
      return SyncOutcome.failed;
    });
    final first = scheduler.run();
    unawaited(scheduler.run());
    scheduler.dispose();
    gate.complete();
    await first;
    expect(calls, 1, reason: 'no retry and no rerun once disposed');
    expect(active(), isEmpty);
  });

  test('ships with production delays and real timers', () async {
    final real = SyncScheduler(scripted);
    addTearDown(real.dispose);
    expect(real.debounce, const Duration(seconds: 2));
    expect(real.firstRetry, const Duration(seconds: 30));
    expect(real.maxRetry, const Duration(minutes: 10));
    real.soon();
    expect(calls, 0);
  });
}
