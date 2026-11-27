import 'dart:async';

import 'package:lyricanki/screens/home_status.dart';
import 'package:lyricanki/screens/sync_screen.dart';
import 'package:lyricanki/services/export_history.dart';
import 'package:lyricanki/services/history_sync.dart';
import 'package:lyricanki/services/sync_scheduler.dart';
import 'package:material_ui/material_ui.dart';

/// The sync half of the home screen: when the history syncs, and what the
/// app bar shows about it.
///
/// Automatic (offline-first rule (b)): a tick on launch, on resume, after
/// each local write, and a backoff retry after a failure. The list still
/// renders from the local log only, so the network is never on the path that
/// paints the home screen -- the old empty-screen bug cannot come back as a
/// timeout. The sync button stays as the manual way in, and the only one
/// that opens the sign-in screen.
///
/// A mixin for the repo's 250-line cap, like `SongSearchHistory`.
mixin SongSearchSync<T extends StatefulWidget>
    on State<T>, WidgetsBindingObserver {
  /// The opened history, or null before it has loaded.
  ExportHistory? get history;

  /// This install's sync id.
  String get deviceId;

  /// Merges the history with the other devices', or null when this device is
  /// not signed in.
  Future<int?> runSync(ExportHistory history, String deviceId);

  /// Shows [status] in the home screen's app bar; null clears it.
  void showStatus(HomeStatus? status);

  /// Re-reads the visible rows after anything changes them.
  void refreshHistory();

  late final SyncScheduler _scheduler = SyncScheduler(
    () => _tick(manual: false),
  );
  StreamSubscription<void>? _writes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scheduler.dispose();
    unawaited(_writes?.cancel());
    super.dispose();
  }

  /// Starts background sync over the just-opened [opened] history: one tick
  /// now, then one after every local write.
  void startAutoSync(ExportHistory opened) {
    _writes = opened.localWrites.listen((_) => _scheduler.soon());
    unawaited(_scheduler.run());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Pulls whatever another device pushed while this one was away.
      // Debounced: a cold start's resume lands on top of the launch tick.
      _scheduler.soon();
    } else if (state != AppLifecycleState.inactive) {
      // Leaving: push a pending write now, the process may not come back.
      // Not on `inactive`, which is mere focus loss (an alt-tab, a dialog).
      _scheduler.flush();
    }
  }

  /// The sync button: the same tick, but it offers sign-in when this device
  /// is not set up.
  Future<void> syncNow() => _scheduler.run(() => _tick(manual: true));

  Future<SyncOutcome> _tick({required bool manual}) async {
    final store = history;
    if (store == null) return SyncOutcome.notSetUp;
    showStatus(const HomeStatus(HomeStatusKind.syncing));
    try {
      final count = await runSync(store, deviceId);
      if (count == null) {
        // Not being set up is a normal state, not an error. Only a tap
        // offers the way in: a launch that opened a screen would nag.
        if (mounted) showStatus(null);
        if (manual && mounted) unawaited(_offerSignIn());
        return SyncOutcome.notSetUp;
      }
      if (mounted) {
        showStatus(HomeStatus(HomeStatusKind.synced, count: count));
        refreshHistory();
      }
      return SyncOutcome.synced;
    } on HistorySyncLocked {
      // Nothing was pulled or pushed. The lock button asks for the shared
      // passphrase and syncs again once it is saved.
      if (mounted) {
        showStatus(HomeStatus(HomeStatusKind.locked, onUnlock: syncNow));
      }
      return SyncOutcome.locked;
    } on Exception catch (error) {
      // Offline, or a rejected token. The local history is untouched and the
      // scheduler retries, so this is a glyph rather than a crash.
      if (mounted) {
        showStatus(HomeStatus(HomeStatusKind.failed, detail: '$error'));
      }
      return SyncOutcome.failed;
    }
  }

  Future<void> _offerSignIn() async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute<void>(builder: (_) => const SyncScreen()));
    // Back from the sign-in screen: a fresh session pulls at once.
    if (mounted) unawaited(_scheduler.run());
  }
}
