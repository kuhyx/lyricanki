// Acceptance measurement for the pinned track. Run by scripts/acceptance.sh
// against the REAL dictionary pack and the live LRCLIB lyrics, which the unit
// suite deliberately does not do: Q8 forbids committing lyrics, so the
// fixture stores only their hash and the derived counts.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:lyricanki/services/pack/pack_reader.dart';
import 'package:lyricanki/services/pipeline/deck_builder.dart';

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Future<String> _fetchLyrics(Object? id) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse('https://lrclib.net/api/get/$id'),
    );
    request.headers.set('User-Agent', 'lyricanki-acceptance');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    return (jsonDecode(body) as Map<String, dynamic>)['plainLyrics'] as String;
  } finally {
    client.close();
  }
}

Future<void> main(List<String> args) async {
  final packPath = args[0];
  final fixture =
      jsonDecode(File(args[1]).readAsStringSync()) as Map<String, dynamic>;

  final lyrics = await _fetchLyrics(fixture['lrclib_id']);
  final digest = sha256.convert(utf8.encode(lyrics)).toString();
  if (digest != fixture['plain_lyrics_sha256']) {
    stderr.writeln('FAIL: LRCLIB lyrics changed; re-measure the fixture.');
    exit(1);
  }

  final draft = DeckBuilder(
    pack: PackReader.open(packPath),
    languageCode: 'es',
  ).build(lyrics);

  final empty = draft.cards.where((c) => c.gloss.trim().isEmpty).toList();
  final unresolved = draft.unresolved.toList()..sort();
  final expected = (fixture['unresolved_surfaces'] as List).cast<String>();

  stdout
    ..writeln('cards      : ${draft.cards.length}')
    ..writeln('empty gloss: ${empty.length}')
    ..writeln('unresolved : ${unresolved.length} $unresolved');

  var ok = true;
  if (draft.cards.length != fixture['expected_notes']) {
    stderr.writeln('FAIL: expected ${fixture['expected_notes']} cards.');
    ok = false;
  }
  if (empty.isNotEmpty) {
    stderr.writeln('FAIL: ${empty.length} cards have an empty gloss.');
    ok = false;
  }
  if (!_sameList(unresolved, expected)) {
    stderr.writeln('FAIL: unresolved changed: $unresolved');
    ok = false;
  }
  if (!ok) exit(1);
  stdout.writeln('Acceptance passed.');
}
