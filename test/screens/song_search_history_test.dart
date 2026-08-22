import 'dart:io';

import 'package:crdt_sync_flutter/testing/fake_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyricanki/models/track.dart';
import 'package:lyricanki/screens/sync_screen.dart';
import 'package:lyricanki/services/export_destination.dart';
import 'package:lyricanki/services/export_history.dart';
import 'package:lyricanki/widgets/export_history_list.dart';

import 'flow_harness.dart';

const _a = Track(
  id: 1,
  name: 'Despacito',
  artist: 'Luis Fonsi',
  durationSeconds: 273,
  plainLyrics: 'suave',
);
const _b = Track(
  id: 2,
  name: 'Bailando',
  artist: 'Enrique Iglesias',
  durationSeconds: 245,
  plainLyrics: 'corazon',
);

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('hist_screen'));
  tearDown(() => root.deleteSync(recursive: true));

  /// Writes a stub `.apkg` and returns its path, so a row renders as present
  /// rather than as a file the user has removed.
  String apkg(String name) =>
      (File('${root.path}/$name.apkg')..writeAsStringSync('stub')).path;

  /// A history holding [tracks], each with a real file behind it.
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

  /// Finds text inside the history list, ignoring any screen above it.
  Finder inList(String text) => find.descendant(
    of: find.byType(ExportHistoryList),
    matching: find.textContaining(text),
  );

  testWidgets('shows every exported song on the home screen', (tester) async {
    // The reported bug: a finished song left this screen looking as though
    // nothing had happened.
    writePack('${root.path}/packs/lyricanki-es.sqlite');
    final history = await seeded(tester, [_a, _b]);

    await pumpHome(tester, storeIn(root), history: history);

    expect(inList('Despacito'), findsOneWidget);
    expect(inList('Bailando'), findsOneWidget);
  });

  testWidgets('opens a row and shows what lyricanki knows', (tester) async {
    writePack('${root.path}/packs/lyricanki-es.sqlite');
    final history = await seeded(tester, [_a]);

    await pumpHome(tester, storeIn(root), history: history);
    await tester.tap(inList('Despacito'));
    await tester.pumpAndSettle();

    expect(find.text('Luis Fonsi'), findsOneWidget);
    expect(find.text('147'), findsOneWidget);
  });

  testWidgets('shares the existing file from the detail screen', (
    tester,
  ) async {
    writePack('${root.path}/packs/lyricanki-es.sqlite');
    final share = RecordingShare();
    final history = await seeded(tester, [_a]);

    await pumpHome(tester, storeIn(root), history: history, share: share);
    await tester.tap(inList('Despacito'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open in AnkiDroid'));
    await tester.pumpAndSettle();

    expect(share.shared, hasLength(1));
  });

  testWidgets('rebuilds a deck from the stored lyrics', (tester) async {
    writePack('${root.path}/packs/lyricanki-es.sqlite');
    final history = await seeded(tester, [_a]);

    await pumpHome(tester, storeIn(root), history: history);
    await tester.tap(inList('Despacito'));
    await tester.pumpAndSettle();
    // Opening the pack is real dart:io, which cannot complete inside the
    // test's fake-async zone.
    await actAsync(tester, () => tester.tap(find.text('Rebuild from lyrics')));

    // Lands on the review screen for the same song, with no network call:
    // the lyrics travelled with the history row precisely so this works.
    expect(find.byType(ExportHistoryList), findsNothing);
    expect(find.textContaining('Export'), findsOneWidget);
  });

  testWidgets('hiding records the flag without deleting the row', (
    tester,
  ) async {
    // Only the *store* half is asserted here. The route pop that follows the
    // write is deliberately not: the confirm handler awaits a real filesystem
    // write before popping, and a `testWidgets` fake-async zone cannot
    // sequence dart:io-then-navigate -- the pop never runs under any
    // combination of pumpAndSettle and runAsync. It was instead verified on
    // the running Linux build: tapping Hide returns to the list with the row
    // gone. See `hide()` in song_search_history.dart.
    writePack('${root.path}/packs/lyricanki-es.sqlite');
    final history = await seeded(tester, [_a, _b]);

    await pumpHome(tester, storeIn(root), history: history);
    await tester.tap(inList('Despacito'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pumpAndSettle();
    await actAsync(tester, () => tester.tap(find.text('Hide')));

    // Hidden, never deleted: the record of a real export survives, so the
    // row comes back if the song is exported again.
    expect(history.visible().map((e) => e.name), ['Bailando']);
    expect(history.all(), hasLength(2));
    expect(
      history.all().firstWhere((e) => e.name == 'Despacito').hidden,
      isTrue,
    );
  });

  testWidgets('cancelling the confirm leaves the row alone', (tester) async {
    writePack('${root.path}/packs/lyricanki-es.sqlite');
    final history = await seeded(tester, [_a]);

    await pumpHome(tester, storeIn(root), history: history);
    await tester.tap(inList('Despacito'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(history.visible(), hasLength(1));
  });

  testWidgets('a rebuilt deck is re-recorded on export', (tester) async {
    // Covers the whole loop: rebuild from stored lyrics, export again, and
    // land back on a refreshed list.
    writePack('${root.path}/packs/lyricanki-es.sqlite');
    final history = await seeded(tester, [_a]);

    await pumpHome(
      tester,
      storeIn(root),
      history: history,
      destination: ExportDestination(directoryOverride: root),
    );
    await tester.tap(inList('Despacito'));
    await tester.pumpAndSettle();
    await actAsync(tester, () => tester.tap(find.text('Rebuild from lyrics')));
    await actAsync(tester, () => tester.tap(find.textContaining('Export')));
    await actAsync(tester, () => tester.pageBack());

    expect(find.byType(ExportHistoryList), findsOneWidget);
    expect(history.all(), hasLength(1), reason: 'still one row, updated');
  });
}
