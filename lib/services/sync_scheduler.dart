import 'dart:async';
import 'dart:math' as math;

/// How one sync tick ended, as far as scheduling the next one cares.
enum SyncOutcome {
  /// Merged and pushed.
  synced,

  /// This device has no session. Waits for the user to sign in.
  notSetUp,

  /// Signed in but no usable end-to-end key. Waits for the passphrase.
  locked,

  /// Offline, a rejected token, a server error: worth trying again later.
  failed,
}

/// One sync attempt.
typedef SyncTick = Future<SyncOutcome> Function();

/// Builds a one-shot timer; tests pass one they fire by hand.
typedef SyncTimerFactory =
    Timer Function(Duration delay, void Function() callback);

/// Decides *when* the history syncs, so nobody has to tap for it.
///
/// Offline-first rule (b): sync runs by itself on launch, on resume and after
/// each local write, and a failure retries later without the user. The local
/// log stays the source of truth throughout -- this only moves it.
///
/// Never two ticks at once: a request that arrives mid-sync is remembered and
/// runs once the current one ends, which is also how a write made during a
/// sync still gets pushed.
class SyncScheduler {
  /// Creates a scheduler around the background [_tick].
  SyncScheduler(
    this._tick, {
    this.debounce = defaultDebounce,
    this.firstRetry = defaultFirstRetry,
    this.maxRetry = defaultMaxRetry,
    SyncTimerFactory? timer,
  }) : _timer = timer ?? Timer.new,
       _retryDelay = firstRetry;

  /// Production [debounce].
  static const Duration defaultDebounce = Duration(seconds: 2);

  /// Production [firstRetry].
  static const Duration defaultFirstRetry = Duration(seconds: 30);

  /// Production [maxRetry].
  static const Duration defaultMaxRetry = Duration(minutes: 10);

  final SyncTick _tick;
  final SyncTimerFactory _timer;

  /// Quiet time after a write before it is pushed, so a burst is one sync.
  final Duration debounce;

  /// Wait before the first retry after a failure; doubles each time.
  final Duration firstRetry;

  /// Cap on the retry wait, so a long outage still retries regularly.
  final Duration maxRetry;

  Duration _retryDelay;
  Timer? _pendingWrite;
  Timer? _pendingRetry;
  bool _running = false;
  bool _again = false;
  bool _disposed = false;

  /// A local write happened: sync once things go quiet.
  void afterWrite() {
    if (_disposed) return;
    _pendingWrite?.cancel();
    _pendingWrite = _timer(debounce, () => unawaited(run()));
  }

  /// Runs a pending write's sync now rather than after the debounce.
  ///
  /// For the app leaving the foreground: Android may kill it before the
  /// timer fires.
  void flush() {
    final pending = _pendingWrite;
    if (pending == null || !pending.isActive) return;
    pending.cancel();
    unawaited(run());
  }

  /// Syncs now with [tick], or the background tick when omitted.
  ///
  /// The manual button passes its own tick (it offers sign-in where the
  /// background one stays quiet), but shares the no-overlap guard and the
  /// retry policy.
  Future<void> run([SyncTick? tick]) async {
    if (_disposed) return;
    if (_running) {
      _again = true;
      return;
    }
    _pendingWrite?.cancel();
    _pendingRetry?.cancel();
    _running = true;
    final SyncOutcome outcome;
    try {
      outcome = await (tick ?? _tick)();
    } finally {
      _running = false;
    }
    if (_disposed) return;
    _arm(outcome);
    if (_again) {
      _again = false;
      await run();
    }
  }

  /// Stops every timer; later requests are ignored.
  void dispose() {
    _disposed = true;
    _pendingWrite?.cancel();
    _pendingRetry?.cancel();
  }

  void _arm(SyncOutcome outcome) {
    if (outcome != SyncOutcome.failed) {
      // A lock or a missing session waits for the user, who acts through
      // the lock button or the sign-in screen; a timer cannot fix either.
      _retryDelay = firstRetry;
      return;
    }
    _pendingRetry = _timer(_retryDelay, () => unawaited(run()));
    final doubled = _retryDelay * 2;
    _retryDelay = Duration(
      microseconds: math.min(doubled.inMicroseconds, maxRetry.inMicroseconds),
    );
  }
}
