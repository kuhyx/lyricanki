import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyricanki/services/export_history.dart';
import 'package:path/path.dart' as p;

/// The defensive half of [ExportHistory]: what happens when the log on disk
/// was written by a different version of the app. Split from
/// `export_history_test.dart` for the repo's 250-line cap.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('lyricanki_hist_bad'));
  tearDown(() => root.deleteSync(recursive: true));

  Future<ExportHistory> openIn(Directory dir) =>
      ExportHistory.open(deviceId: 'test', directoryOverride: dir);

  group('a log written by another version', () {
    /// Writes [json] as the on-disk log, bypassing ExportHistory entirely.
    void seed(String json) =>
        File(p.join(root.path, ExportHistory.fileName)).writeAsStringSync(json);

    const hlc = '2026-08-22T15:34:20.858Z-0000-other';

    test('substitutes defaults for wrongly-typed fields', () async {
      // Every field here has the wrong type. None of this is reachable
      // through record(), which always writes well-typed values -- but a log
      // merged from a device running a different version of the app can
      // carry anything, and one bad row must not take the whole list down.
      seed(
        '{"7":{"id":"7","fields":{'
        '"name":[42,"$hlc"],'
        '"artist":[null,"$hlc"],'
        '"path":[true,"$hlc"],'
        '"cardCount":["lots","$hlc"],'
        '"exportedAt":["not a date","$hlc"],'
        '"lyrics":[[],"$hlc"],'
        '"hidden":["yes","$hlc"]'
        '},"deleted":false,"deleted_hlc":null}}',
      );

      final entry = (await openIn(root)).all().single;

      expect(entry.trackId, 7);
      expect(entry.name, isEmpty);
      expect(entry.artist, isEmpty);
      expect(entry.path, isEmpty);
      expect(entry.cardCount, 0);
      expect(entry.exportedAt, DateTime.fromMillisecondsSinceEpoch(0));
      expect(entry.lyrics, isEmpty);
      // Anything that is not the boolean true is not hidden: a row the user
      // never hid must never vanish because of a type confusion.
      expect(entry.hidden, isFalse);
    });

    test('rounds a card count that arrived as a double', () async {
      // JSON has one number type, so a count can come back as 147.0.
      seed(
        '{"8":{"id":"8","fields":{"cardCount":[147.4,"$hlc"]},'
        '"deleted":false,"deleted_hlc":null}}',
      );

      expect((await openIn(root)).all().single.cardCount, 147);
    });

    test('falls back to id 0 for a non-numeric record id', () async {
      seed(
        '{"not-a-number":{"id":"not-a-number","fields":{},'
        '"deleted":false,"deleted_hlc":null}}',
      );

      expect((await openIn(root)).all().single.trackId, 0);
    });

    test('skips tombstoned records', () async {
      // Nothing in this app writes one, but a future version might.
      seed(
        '{"9":{"id":"9","fields":{"name":["Gone","$hlc"]},'
        '"deleted":true,"deleted_hlc":"$hlc"}}',
      );

      expect((await openIn(root)).all(), isEmpty);
    });
  });
}
