import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyricanki/models/export_entry.dart';
import 'package:lyricanki/screens/export_detail_screen.dart';

ExportEntry entry({String path = '/present.apkg', String lyrics = 'uno dos'}) =>
    ExportEntry(
      trackId: 36856755,
      name: 'Despacito',
      artist: 'Luis Fonsi',
      path: path,
      cardCount: 147,
      exportedAt: DateTime(2026, 8, 22, 17, 45),
      lyrics: lyrics,
    );

Future<void> pump(
  WidgetTester tester, {
  ExportEntry? which,
  bool packReady = true,
  Future<void> Function()? onShare,
  Future<void> Function()? onRebuild,
  Future<void> Function()? onHide,
}) => tester.pumpWidget(
  MaterialApp(
    home: ExportDetailScreen(
      entry: which ?? entry(),
      packReady: packReady,
      fileExists: (p) => p != '/gone.apkg',
      onShare: onShare ?? () async {},
      onRebuild: onRebuild ?? () async {},
      onHide: onHide ?? () async {},
    ),
  ),
);

void main() {
  testWidgets('shows the stats lyricanki actually owns', (tester) async {
    await pump(tester);

    expect(find.text('Luis Fonsi'), findsOneWidget);
    expect(find.text('147'), findsOneWidget);
    expect(find.text('2026-08-22 17:45'), findsOneWidget);
    // Two whitespace-separated words in the fixture's lyrics.
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('offers no training figure it cannot know', (tester) async {
    // Reviewing happens inside AnkiDroid's own collection, which this app
    // cannot read. A blank that can never fill is worse than its absence.
    await pump(tester);

    expect(find.textContaining('Trained'), findsNothing);
    expect(find.textContaining('Reviewed'), findsNothing);
  });

  testWidgets('hands the existing file to another app', (tester) async {
    var shared = 0;
    await pump(tester, onShare: () async => shared++);

    await tester.tap(find.text('Open in AnkiDroid'));

    expect(shared, 1);
  });

  testWidgets('hides the share button when the file is gone', (tester) async {
    await pump(tester, which: entry(path: '/gone.apkg'));

    expect(find.text('Open in AnkiDroid'), findsNothing);
    expect(find.text('Removed'), findsOneWidget);
    expect(find.text('Rebuild deck'), findsOneWidget);
  });

  testWidgets('rebuilds on request', (tester) async {
    var rebuilt = 0;
    await pump(tester, onRebuild: () async => rebuilt++);

    await tester.tap(find.text('Rebuild from lyrics'));

    expect(rebuilt, 1);
  });

  testWidgets('disables rebuild with a reason when no pack', (tester) async {
    // Rebuilding resolves every word against the dictionary, so without one
    // it would fail at tap time instead of saying why up front.
    await pump(tester, packReady: false);

    final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(button.onPressed, isNull);
    expect(
      find.text('Download the dictionary pack to rebuild this deck.'),
      findsOneWidget,
    );
  });

  testWidgets('hides only after the user confirms', (tester) async {
    var hidden = 0;
    await pump(tester, onHide: () async => hidden++);

    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(hidden, 0, reason: 'cancelling must not hide the row');

    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide'));
    await tester.pumpAndSettle();

    expect(hidden, 1);
  });
}
