import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyricanki/screens/song_search_screen.dart';
import 'package:lyricanki/services/lrclib_client.dart';
import 'package:lyricanki/services/pack/pack_store.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('lyricanki_home'));
  tearDown(() => root.deleteSync(recursive: true));

  PackStore storeIn(Directory dir) => PackStore(
    httpClient: MockClient((_) async => http.Response('', 200)),
    directoryOverride: dir,
  );

  LrclibClient emptyClient() => LrclibClient(
    httpClient: MockClient(
      (_) async => http.Response.bytes(utf8.encode('[]'), 200),
    ),
  );

  /// Places a stub pack on disk so the screen sees one installed.
  ///
  /// Written synchronously: awaiting real dart:io inside a testWidgets body
  /// deadlocks the fake-async zone.
  void installStubPack(Directory dir) {
    final packs = Directory('${dir.path}/packs')..createSync(recursive: true);
    File(
      '${packs.path}/lyricanki-es.sqlite',
    ).writeAsStringSync('SQLite format 3');
  }

  /// Pumps the screen and lets its initState pack check actually run.
  ///
  /// The check touches the filesystem, and real dart:io work cannot complete
  /// inside the test's fake-async zone -- without runAsync the pump never
  /// settles.
  Future<void> pump(WidgetTester tester, PackStore store) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SongSearchScreen(client: emptyClient(), store: store),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }

  testWidgets('blocks deck building until a pack is installed', (tester) async {
    // Without a dictionary there is nothing to resolve words against, so the
    // button is disabled rather than failing later with a SQLite error.
    final store = storeIn(root);
    await pump(tester, store);
    expect(find.text('No dictionary yet'), findsOneWidget);
    final fab = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton),
    );
    expect(fab.onPressed, isNull);
  });

  testWidgets('enables deck building once a pack is present', (tester) async {
    installStubPack(root);
    final store = storeIn(root);
    await pump(tester, store);
    expect(find.text('Ready'), findsOneWidget);
    final fab = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton),
    );
    expect(fab.onPressed, isNotNull);
  });

  testWidgets('offers the pack screen from the app bar', (tester) async {
    final store = storeIn(root);
    await pump(tester, store);
    // The same icon also appears in the empty state, so target the app bar's.
    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.storage_outlined),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Dictionary pack'), findsOneWidget);
  });

  testWidgets('opens the track picker when a pack is installed', (
    tester,
  ) async {
    installStubPack(root);
    final store = storeIn(root);
    await pump(tester, store);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('Find a song'), findsWidgets);
    expect(find.byType(TextField), findsOneWidget);
  });
}
