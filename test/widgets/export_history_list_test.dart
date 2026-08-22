import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyricanki/models/export_entry.dart';
import 'package:lyricanki/widgets/export_history_list.dart';

ExportEntry entry(int id, String name, {String path = '/present.apkg'}) =>
    ExportEntry(
      trackId: id,
      name: name,
      artist: 'Artist',
      path: path,
      cardCount: 147,
      exportedAt: DateTime(2026, 8, 22),
      lyrics: 'la la',
    );

Future<void> pump(
  WidgetTester tester,
  List<ExportEntry> entries, {
  void Function(ExportEntry)? onOpen,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: ExportHistoryList(
        entries: entries,
        onOpen: onOpen ?? (_) {},
        fileExists: (p) => p != '/gone.apkg',
      ),
    ),
  ),
);

void main() {
  testWidgets('shows every entry it is given', (tester) async {
    await pump(tester, [entry(1, 'Despacito'), entry(2, 'Bailando')]);

    expect(find.textContaining('Despacito'), findsOneWidget);
    expect(find.textContaining('Bailando'), findsOneWidget);
  });

  testWidgets('marks a row whose file is gone', (tester) async {
    await pump(tester, [entry(1, 'Gone', path: '/gone.apkg')]);

    expect(find.text('File removed — tap to rebuild'), findsOneWidget);
  });

  testWidgets('shows the card count when the file is present', (tester) async {
    await pump(tester, [entry(1, 'Despacito')]);

    expect(find.text('147 cards · 2026-08-22'), findsOneWidget);
  });

  testWidgets('reports the tapped entry', (tester) async {
    final tapped = <ExportEntry>[];
    await pump(tester, [entry(1, 'Despacito')], onOpen: tapped.add);

    await tester.tap(find.textContaining('Despacito'));

    expect(tapped.single.trackId, 1);
  });
}
