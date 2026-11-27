import 'dart:io';

import 'package:crdt_sync/crdt_sync.dart' show E2eLockReason;
import 'package:crdt_sync_flutter/testing/fake_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyricanki/models/track.dart';
import 'package:lyricanki/screens/sync_screen.dart';
import 'package:lyricanki/services/export_history.dart';
import 'package:lyricanki/services/history_sync.dart';
import 'package:lyricanki/services/sync_scheduler.dart';
import 'package:material_ui/material_ui.dart';

import 'flow_harness.dart';

/// Sync with nobody tapping anything: on launch, after a write, on resume,
/// and again after a failure. Offline-first rule (b), kuhy 2026-11-27.
const _a = Track(
  id: 1,
  name: 'Despacito',
  artist: 'Luis Fonsi',
  durationSeconds: 273,
  plainLyrics: 'suave',
);

void main() {
  late Directory root;
  late int calls;

  setUp(() {
    root = Directory.systemTemp.createTempSync('hist_autosync');
    calls = 0;
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<ExportHistory> seeded(WidgetTester tester) async =>
      (await tester.runAsync(() async {
        final history = await historyIn(root);
        await history.record(track: _a, path: '/a.apkg', cardCount: 3);
        return history;
      }))!;

  Future<ExportHistory> launch(
    WidgetTester tester,
    Future<int?> Function() tick,
  ) async {
    writePack('${root.path}/packs/lyricanki-es.sqlite');
    final history = await seeded(tester);
    await pumpHome(
      tester,
      storeIn(root),
      history: history,
      syncHistory: (_, _) {
        calls++;
        return tick();
      },
    );
    await tester.pump();
    return history;
  }

  testWidgets('syncs on launch without a tap', (tester) async {
    await launch(tester, () async => 4);

    expect(calls, 1);
    expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
  });

  testWidgets('a burst of writes syncs once, after the debounce', (
    tester,
  ) async {
    final history = await launch(tester, () async => 1);
    await tester.runAsync(() async {
      await history.setHidden(_a.id, hidden: true);
      await history.setHidden(_a.id, hidden: false);
    });
    await tester.pump();
    expect(calls, 1, reason: 'never on the write path itself');

    await tester.pump(SyncScheduler.defaultDebounce);
    expect(calls, 2);
  });

  testWidgets('a failed sync retries later with no tap', (tester) async {
    await launch(
      tester,
      () async => calls == 1 ? throw const SocketException('offline') : 2,
    );
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);

    await tester.pump(SyncScheduler.defaultFirstRetry);
    await tester.pump();
    expect(calls, 2);
    expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
  });

  testWidgets('syncs again when the app comes back', (tester) async {
    await launch(tester, () async => 1);
    tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(calls, 1, reason: 'nothing pending, so nothing to push');

    tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(calls, 2);
  });

  testWidgets('pushes a pending write at once when the app is left', (
    tester,
  ) async {
    final history = await launch(tester, () async => 1);
    await tester.runAsync(() => history.setHidden(_a.id, hidden: true));
    await tester.pump();

    // Android may kill the process before the debounce fires.
    tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(calls, 2);
    tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('a device that is not set up stays quiet', (tester) async {
    await launch(tester, () async => null);

    // Only the button offers sign-in; launching must not push a screen.
    expect(calls, 1);
    expect(find.byType(SyncScreen), findsNothing);
    expect(find.byIcon(Icons.cloud_off_outlined), findsNothing);
  });

  testWidgets('back from the sign-in screen, it syncs at once', (tester) async {
    installFakeSecureStorage();
    await launch(tester, () async => null);
    await tester.tap(find.byIcon(Icons.sync));
    // Pumped, never settled: the sign-in screen animates a keystore probe.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(SyncScreen), findsOneWidget);
    expect(calls, 2);

    Navigator.of(tester.element(find.byType(SyncScreen))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(calls, 3, reason: 'a fresh session pulls without another tap');
  });

  testWidgets('a lock shows the button and waits for the passphrase', (
    tester,
  ) async {
    await launch(
      tester,
      () async => throw const HistorySyncLocked(E2eLockReason.needsPassphrase),
    );
    expect(find.byIcon(Icons.lock), findsOneWidget);

    await tester.pump(SyncScheduler.defaultMaxRetry);
    expect(calls, 1, reason: 'retrying cannot fix a missing key');
  });
}
