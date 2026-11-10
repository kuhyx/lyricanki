import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyricanki/models/export_entry.dart';
import 'package:lyricanki/widgets/export_history_list.dart';

import '../text_free.dart';

/// The textgate guard for the home list (split from the screen guard for the
/// 250-line cap): rows show the song, its card count and date, and nothing
/// Claude wrote around them.
void main() {
  testWidgets('home list with a present and a missing export', (tester) async {
    ExportEntry entry(int id, String path) => ExportEntry(
      trackId: id,
      name: 'Despacito',
      artist: 'Luis Fonsi',
      path: path,
      cardCount: 146,
      exportedAt: DateTime(2026, 11, 10),
      lyrics: 'uno',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportHistoryList(
            entries: <ExportEntry>[entry(1, '/a.apkg'), entry(2, '/gone')],
            onOpen: (_) {},
            fileExists: (path) => path == '/a.apkg',
          ),
        ),
      ),
    );
    expectNoWords(tester, content: const {'Despacito', 'Luis Fonsi'});
  });
}
