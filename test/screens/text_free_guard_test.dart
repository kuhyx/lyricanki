import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyricanki/models/export_entry.dart';
import 'package:lyricanki/models/vocab_card.dart';
import 'package:lyricanki/screens/export_detail_screen.dart';
import 'package:lyricanki/screens/pack_screen.dart';
import 'package:lyricanki/screens/review_screen.dart';
import 'package:lyricanki/screens/track_picker_screen.dart';
import 'package:lyricanki/services/deck_session.dart';
import 'package:lyricanki/services/export_history.dart';
import 'package:lyricanki/services/lrclib_client.dart';
import 'package:lyricanki/services/pack/pack_store.dart';

import '../text_free.dart';
import 'flow_harness.dart';
import 'review_screen_test.dart' show sessionWith;

/// The textgate guard: every lyricanki screen, in the states that used to
/// paint sentences (errors, sync outcomes, rebuilt decks, unresolved words,
/// credits, the hide confirmation), shows no word Claude wrote.
///
/// The sync settings screen is not here: its text lives in the shared
/// `sync_settings_ui` package (kuhyx/utils), not in this repo.
const _card = VocabCard(
  lemma: 'corazón',
  pos: 'noun',
  gloss: 'heart',
  line: 'Corazón suave',
);

ExportEntry _entry({List<VocabCard> cards = const <VocabCard>[]}) =>
    ExportEntry(
      trackId: 36856755,
      name: 'Despacito',
      artist: 'Luis Fonsi',
      path: '/present.apkg',
      cardCount: 147,
      exportedAt: DateTime(2026, 8, 22, 17, 45),
      lyrics: 'uno dos',
      cards: cards,
      unresolved: const <String>['ay'],
    );

const _detailContent = <String>{
  'Despacito',
  'Luis Fonsi',
  '/present.apkg',
  'corazón',
  'noun',
  'heart',
  'Corazón suave',
  'ay',
};

Set<String> _sessionContent(DeckSession session) => <String>{
  ?session.track?.name,
  for (final e in session.entries) ...<String>[
    e.card.lemma,
    e.card.pos,
    e.card.gloss,
    e.card.line,
  ],
  ...session.unresolved,
};

Future<void> _pumpDetail(
  WidgetTester tester,
  ExportEntry entry, {
  bool packReady = true,
  List<VocabCard>? derived,
}) => tester.pumpWidget(
  MaterialApp(
    home: ExportDetailScreen(
      entry: entry,
      packReady: packReady,
      derivedCards: derived,
      fileExists: (_) => true,
      onShare: () async {},
      onRebuild: () async {},
      onHide: () async {},
    ),
  ),
);

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('lyricanki_guard'));
  tearDown(() => root.deleteSync(recursive: true));

  testWidgets('pack screen: idle, failed download and credits', (tester) async {
    final store = PackStore(
      httpClient: MockClient.streaming(
        (_, _) async =>
            http.StreamedResponse(Stream<List<int>>.value(<int>[]), 404),
      ),
      directoryOverride: root,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PackScreen(store: store, language: 'es'),
      ),
    );
    await tester.pumpAndSettle();
    expectNoWords(tester, content: const {'es'});

    await tester.runAsync(
      () => tester.tap(find.byKey(const Key('pack-download'))),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    expectNoWords(tester, content: const {'es'});
    store.close();
  });

  testWidgets('track picker: offline', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TrackPickerScreen(
          client: LrclibClient(
            httpClient: MockClient((_) async => http.Response('', 500)),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Despacito');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    expectNoWords(tester, content: const {'Despacito'});
  });

  testWidgets('review screen: unresolved words and export button', (
    tester,
  ) async {
    final session = sessionWith('Corazón suave ay oh');
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(session: session, onExport: () async => '2 · 3 KB'),
      ),
    );
    expectNoWords(tester, content: _sessionContent(session));

    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expectNoWords(tester, content: _sessionContent(session));
    session.pack.close();
  });

  group('export detail', () {
    testWidgets('exact deck', (tester) async {
      await _pumpDetail(tester, _entry(cards: const <VocabCard>[_card]));
      expectNoWords(tester, content: _detailContent);
    });

    testWidgets('rebuilt deck that differs from the export', (tester) async {
      await _pumpDetail(tester, _entry(), derived: const <VocabCard>[_card]);
      expectNoWords(tester, content: _detailContent);
    });

    testWidgets('no word list and no pack', (tester) async {
      await _pumpDetail(tester, _entry(), packReady: false);
      expectNoWords(tester, content: _detailContent);
    });

    testWidgets('hide confirmation', (tester) async {
      await _pumpDetail(tester, _entry());
      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expectNoWords(tester, content: _detailContent);
    });
  });

  group('home screen', () {
    Future<ExportHistory> history(WidgetTester tester) async =>
        (await tester.runAsync(() => historyIn(root)))!;

    testWidgets('sync failure on an empty history', (tester) async {
      writePack('${root.path}/packs/lyricanki-es.sqlite');
      await pumpHome(
        tester,
        storeIn(root),
        history: await history(tester),
        syncHistory: (_, _) async => throw const SocketException('offline'),
      );
      await tester.tap(find.byIcon(Icons.sync));
      await tester.pumpAndSettle();
      expectNoWords(tester);
    });

    testWidgets('sync success on an empty history', (tester) async {
      writePack('${root.path}/packs/lyricanki-es.sqlite');
      await pumpHome(
        tester,
        storeIn(root),
        history: await history(tester),
        syncHistory: (_, _) async => 4,
      );
      await tester.tap(find.byIcon(Icons.sync));
      await tester.pumpAndSettle();
      expectNoWords(tester);
    });

    testWidgets('lyrics fetch failure after picking a track', (tester) async {
      writePack('${root.path}/packs/lyricanki-es.sqlite');
      final client = LrclibClient(
        httpClient: MockClient((request) async {
          if (request.url.path.contains('/search')) {
            return http.Response.bytes(
              utf8.encode(jsonEncode(<Map<String, dynamic>>[track])),
              200,
            );
          }
          return http.Response('', 404);
        }),
      );
      await pumpHome(
        tester,
        storeIn(root),
        client: client,
        history: await history(tester),
      );
      await pickTrack(tester);
      expectNoWords(tester);
    });
  });
}
