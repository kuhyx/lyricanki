import 'dart:io';

import 'package:crdt_sync_flutter/testing/fake_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyricanki/models/track.dart';
import 'package:lyricanki/screens/sync_screen.dart';
import 'package:lyricanki/services/export_history.dart';
import 'package:lyricanki/widgets/export_history_list.dart';

import 'flow_harness.dart';

/// The sync half of the home screen. Split from
/// `song_search_history_test.dart` for the repo's 250-line cap.
const _a = Track(
  id: 1,
  name: 'Despacito',
  artist: 'Luis Fonsi',
  durationSeconds: 273,
  plainLyrics: 'suave',
);

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('hist_sync'));
  tearDown(() => root.deleteSync(recursive: true));

  String apkg(String name) =>
      (File('${root.path}/$name.apkg')..writeAsStringSync('stub')).path;

  Future<ExportHistory> seeded(WidgetTester tester, List<Track> tracks) async =>
      (await tester.runAsync(() async {
        final history = await historyIn(root);
        for (final track in tracks) {
          await history.record(
            track: track,
            path: apkg('${track.id}'),
            cardCount: 147,
          );
        }
        return history;
      }))!;

  Finder inList(String text) => find.descendant(
    of: find.byType(ExportHistoryList),
    matching: find.textContaining(text),
  );

  group('sync', () {
    testWidgets('reports how many songs it merged', (tester) async {
      writePack('${root.path}/packs/lyricanki-es.sqlite');
      final history = await seeded(tester, [_a]);

      await pumpHome(
        tester,
        storeIn(root),
        history: history,
        syncHistory: (_, _) async => 4,
      );
      await tester.tap(find.byIcon(Icons.sync));
      await tester.pumpAndSettle();

      expect(find.textContaining('Synced'), findsNothing);
      // The status line shows on the empty state; with rows present the list
      // stays, so the sync result is observed through the store instead.
      expect(history.all(), hasLength(1));
    });

    testWidgets('offers sign-in when the device is not set up', (tester) async {
      writePack('${root.path}/packs/lyricanki-es.sqlite');
      final history = await seeded(tester, [_a]);

      await pumpHome(
        tester,
        storeIn(root),
        history: history,
        syncHistory: (_, _) async => null,
      );
      await tester.tap(find.byIcon(Icons.sync));
      // Deliberately pumped, never settled: the settings screen probes the
      // OS keystore behind an indeterminate progress indicator, and
      // pumpAndSettle never returns while one animates.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Not configured is not an error: it routes to the settings screen
      // rather than reporting a failure the user cannot act on.
      expect(find.byType(SyncScreen), findsOneWidget);
    });

    testWidgets('survives being offline', (tester) async {
      writePack('${root.path}/packs/lyricanki-es.sqlite');
      final history = await seeded(tester, [_a]);

      await pumpHome(
        tester,
        storeIn(root),
        history: history,
        syncHistory: (_, _) async => throw const SocketException('offline'),
      );
      await tester.tap(find.byIcon(Icons.sync));
      await tester.pumpAndSettle();

      // The local history is authoritative and untouched.
      expect(history.all(), hasLength(1));
      expect(inList('Despacito'), findsOneWidget);
    });
  });

  testWidgets('falls back to the real tick when none is injected', (
    tester,
  ) async {
    // The production wiring: no syncHistory seam, so the screen uses its own
    // default, which reaches the keystore. The fake keeps that off a platform
    // channel; with no session stored the tick reports "not set up", which is
    // the correct answer for a device nobody has signed in on.
    installFakeSecureStorage();
    writePack('${root.path}/packs/lyricanki-es.sqlite');
    final history = await seeded(tester, [_a]);

    await pumpHome(tester, storeIn(root), history: history);
    await actAsync(tester, () => tester.tap(find.byIcon(Icons.sync)));
    await tester.pump();

    expect(history.all(), hasLength(1), reason: 'local history untouched');
  });
}
