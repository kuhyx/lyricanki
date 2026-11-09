/// Spanish morphology rules that recover words Wiktionary does not list.
///
/// Two gaps show up immediately in song lyrics, and neither is a pruning
/// artifact — no pack size fixes them, because the source extract has no entry
/// at all:
///
/// * **Diminutives.** `despacito` (the song title) and `suavecito` are absent;
///   their bases `despacio` and `suave` are present with English glosses.
/// * **Colloquial elision.** Sung Spanish drops the final *s* of the first
///   person plural: `vamo` for `vamos`.
///
/// Each rule applies only when the rewritten form is already known to the
/// pack, so a rule can recover a word but never invent one.
///
/// Mirrors `tools/pack_builder/morphology.py`.
library;

/// Diminutive suffixes. Spanish inserts `-c-` before the suffix after certain
/// stems (`suave` -> `suavecito`), so both plain and `-c-` forms are listed.
const List<String> diminutiveSuffixes = <String>[
  'ito',
  'ita',
  'itos',
  'itas',
  'cito',
  'cita',
  'citos',
  'citas',
  'ecito',
  'ecita',
];

/// Endings the recovered base may take.
const List<String> baseEndings = <String>['o', 'a', 'e', 'io', 'ia', ''];

/// Yields plausible base forms for the diminutive [surface].
Iterable<String> diminutiveBases(String surface) sync* {
  final seen = <String>{};
  for (final suffix in diminutiveSuffixes) {
    if (!surface.endsWith(suffix)) continue;
    final stem = surface.substring(0, surface.length - suffix.length);
    // 2-letter stems are allowed (`ojitos` -> `ojo`) but never bare: `os`
    // is a pronoun, not the base of `ositos`.
    if (stem.length < 2) continue;
    for (final ending in baseEndings) {
      if (ending.isEmpty && stem.length < 3) continue;
      final candidate = stem + ending;
      if (candidate == surface) continue;
      if (seen.add(candidate)) yield candidate;
    }
  }
}

/// Matches a sung participle with its `d` dropped: `esta'o`, `cansa’a`.
final RegExp _droppedD = RegExp(r"['’]([oa]s?)$");

/// Yields base forms for a colloquially elided [surface] (`vamo` -> `vamos`).
Iterable<String> elisionBases(String surface) sync* {
  final participle = _droppedD.firstMatch(surface);
  if (participle != null) {
    yield '${surface.substring(0, participle.start)}d${participle.group(1)}';
  }
  // -mos -> -mo is the common sung elision. Restoring the s is safe because
  // the result must still be a known form to be accepted.
  if (surface.endsWith('mo')) {
    yield '${surface}s';
  }
}

/// Returns a known base for [surface], or `null`.
///
/// Diminutives are tried before elisions because they are far more common in
/// lyrics and cannot overlap: no diminutive suffix ends in `mo`.
String? recover(String surface, bool Function(String candidate) isKnown) {
  for (final candidate in diminutiveBases(surface)) {
    if (isKnown(candidate)) return candidate;
  }
  for (final candidate in elisionBases(surface)) {
    if (isKnown(candidate)) return candidate;
  }
  return null;
}
