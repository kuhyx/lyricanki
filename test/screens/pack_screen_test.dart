import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyricanki/screens/pack_screen.dart';
import 'package:lyricanki/services/pack/pack_store.dart';

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
    expect(find.text('Download pack'), findsOneWidget);
    expect(find.textContaining('Not installed'), findsOneWidget);
    store.close();
  });

  testWidgets('downloading installs the pack and offers removal', (
    tester,
  ) async {
    final store = storeServing(utf8.encode('data'));
    await pump(tester, store);
    await tester.runAsync(() async {
      await tester.tap(find.text('Download pack'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(find.text('Remove pack'), findsOneWidget);
    expect(await store.hasPack('es'), isTrue);
    store.close();
  });

  testWidgets('removing deletes the pack', (tester) async {
    final store = storeServing(utf8.encode('data'));
    await pump(tester, store);
    await tester.runAsync(() async {
      await tester.tap(find.text('Download pack'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.text('Remove pack'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(find.text('Download pack'), findsOneWidget);
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
    await tester.tap(find.text('Download pack'));
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
    await tester.runAsync(() async {
      await tester.tap(find.text('Download pack'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(find.textContaining('404'), findsOneWidget);
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
    await tester.runAsync(() async {
      await tester.tap(find.text('Download pack'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(changes, 1);
    store.close();
  });

  group('attribution', () {
    testWidgets('credits Wiktionary and names CC BY-SA, as required', (
      tester,
    ) async {
      // Not decoration: the pack is CC BY-SA data, and the licence requires
      // both attribution and naming the licence.
      final store = storeServing(utf8.encode('data'));
      await pump(tester, store);
      expect(find.textContaining('Wiktionary'), findsOneWidget);
      expect(find.textContaining('kaikki.org'), findsOneWidget);
      expect(find.textContaining('CC BY-SA'), findsOneWidget);
      store.close();
    });

    testWidgets('credits LRCLIB for the lyrics', (tester) async {
      final store = storeServing(utf8.encode('data'));
      await pump(tester, store);
      expect(find.textContaining('LRCLIB'), findsOneWidget);
      store.close();
    });

    testWidgets('states that lyrics are not stored or shared', (tester) async {
      // Q8: personal use only, no lyrics leave the device.
      final store = storeServing(utf8.encode('data'));
      await pump(tester, store);
      expect(find.textContaining('never stored or shared'), findsOneWidget);
      store.close();
    });
  });
}
