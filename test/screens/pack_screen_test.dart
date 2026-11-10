import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyricanki/screens/pack_screen.dart';
import 'package:lyricanki/services/attributions.dart';
import 'package:lyricanki/services/pack/pack_store.dart';

import 'real_async.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('lyricanki_packui'));
  tearDown(() => root.deleteSync(recursive: true));

  PackStore storeServing(List<int> body, {int status = 200}) => PackStore(
    httpClient: MockClient.streaming(
      (_, _) async => http.StreamedResponse(
        Stream<List<int>>.fromIterable(<List<int>>[body]),
        status,
        contentLength: body.length,
      ),
    ),
    directoryOverride: root,
  );

  Future<void> pump(WidgetTester tester, PackStore store) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PackScreen(store: store, language: 'es'),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('offers a download when no pack is installed', (tester) async {
    final store = storeServing(utf8.encode('data'));
    await pump(tester, store);
    expect(find.byKey(const Key('pack-download')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('pack-download')),
        matching: find.byIcon(Icons.download_outlined),
      ),
      findsOneWidget,
    );
    store.close();
  });

  testWidgets('downloading installs the pack and offers removal', (
    tester,
  ) async {
    final store = storeServing(utf8.encode('data'));
    await pump(tester, store);
    await tester.runAsync(
      () => tester.tap(find.byKey(const Key('pack-download'))),
    );
    await pumpUntil(
      tester,
      () => find.byKey(const Key('pack-remove')).evaluate().isNotEmpty,
    );
    expect(find.byKey(const Key('pack-remove')), findsOneWidget);
    expect(await store.hasPack('es'), isTrue);
    store.close();
  });

  testWidgets('removing deletes the pack', (tester) async {
    final store = storeServing(utf8.encode('data'));
    await pump(tester, store);
    await tester.runAsync(
      () => tester.tap(find.byKey(const Key('pack-download'))),
    );
    await pumpUntil(
      tester,
      () => find.byKey(const Key('pack-remove')).evaluate().isNotEmpty,
    );
    await tester.runAsync(
      () => tester.tap(find.byKey(const Key('pack-remove'))),
    );
    await pumpUntil(
      tester,
      () => find.byKey(const Key('pack-download')).evaluate().isNotEmpty,
    );
    expect(find.byKey(const Key('pack-download')), findsOneWidget);
    expect(await store.hasPack('es'), isFalse);
    store.close();
  });

  testWidgets('shows a progress bar while the download runs', (tester) async {
    // Streams in two chunks with a gap, so a frame is guaranteed to land
    // while _busy is still true.
    final store = PackStore(
      httpClient: MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          Stream<List<int>>.fromIterable(<List<int>>[
            utf8.encode('aaaa'),
            utf8.encode('bbbb'),
          ]).asyncMap((chunk) async {
            await Future<void>.delayed(const Duration(milliseconds: 30));
            return chunk;
          }),
          200,
          contentLength: 8,
        ),
      ),
      directoryOverride: root,
    );
    await pump(tester, store);
    await tester.tap(find.byKey(const Key('pack-download')));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    store.close();
  });

  testWidgets('reports a failed download instead of failing silently', (
    tester,
  ) async {
    final store = storeServing(utf8.encode(''), status: 404);
    await pump(tester, store);
    await tester.runAsync(
      () => tester.tap(find.byKey(const Key('pack-download'))),
    );
    await pumpUntil(
      tester,
      () => find.byKey(const Key('pack-error')).evaluate().isNotEmpty,
    );
    // Glyph on screen, the HTTP cause spoken only.
    final error = tester.widget<Icon>(find.byKey(const Key('pack-error')));
    expect(error.icon, Icons.cloud_off_outlined);
    expect(error.semanticLabel, contains('404'));
    expect(find.textContaining('404'), findsNothing);
    store.close();
  });

  testWidgets('notifies the caller when the pack changes', (tester) async {
    var changes = 0;
    final store = storeServing(utf8.encode('data'));
    await tester.pumpWidget(
      MaterialApp(
        home: PackScreen(
          store: store,
          language: 'es',
          onChanged: () => changes++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => tester.tap(find.byKey(const Key('pack-download'))),
    );
    await pumpUntil(tester, () => changes > 0);
    expect(changes, 1);
    store.close();
  });

  group('attribution', () {
    // Not decoration: the pack is CC BY-SA data, and the licence requires
    // both attribution and naming the licence. The notices sit in the
    // licence page behind the (c) glyph rather than painted on the screen.
    Future<String> notices() async {
      final entries = await LicenseRegistry.licenses.toList();
      return <String>[
        for (final e in entries)
          for (final p in e.paragraphs) p.text,
      ].join('\n');
    }

    testWidgets('the (c) glyph opens the licence page', (tester) async {
      final store = storeServing(utf8.encode('data'));
      await pump(tester, store);
      await tester.tap(find.byKey(const Key('pack-credits')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(LicensePage), findsOneWidget);
      store.close();
    });

    test(
      'credits Wiktionary via kaikki.org under CC BY-SA, and LRCLIB',
      () async {
        registerAttributions();
        registerAttributions(); // idempotent: a second visit adds nothing
        final text = await notices();
        expect(text, contains('Wiktionary via kaikki.org'));
        expect(text, contains('CC BY-SA'));
        expect(text, contains('LRCLIB'));
        expect('Wiktionary via kaikki.org'.allMatches(text), hasLength(1));
      },
    );
  });
}
