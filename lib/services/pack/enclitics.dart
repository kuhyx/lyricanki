/// Splitting Spanish enclitic pronoun clusters off a verb.
///
/// Spanish attaches object pronouns to the end of infinitives, gerunds and
/// imperatives (`dámelo` = *da* + *me* + *lo*), and the pack's `forms` table
/// stores the bare verb form, not the cluster. Splitting is therefore a
/// prerequisite for resolving them at all.
library;

/// The pronouns that attach to a verb, longest first so `nos` is tried before
/// `os` and a wrong shorter split is never taken.
const List<String> encliticPronouns = <String>[
  'melo',
  'mela',
  'selo',
  'sela',
  'telo',
  'tela',
  'nos',
  'les',
  'los',
  'las',
  'le',
  'lo',
  'la',
  'me',
  'te',
  'se',
  'os',
];

/// Yields candidate stems for [surface], longest stem first.
///
/// An accented imperative loses its accent when the pronouns come off
/// (`dámelo` -> `da`, `quítate` -> `quita`), so accented vowels are also
/// restored to their bare forms as a second candidate.
Iterable<String> splitEnclitics(String surface) sync* {
  for (final pronoun in encliticPronouns) {
    if (!surface.endsWith(pronoun) || surface.length <= pronoun.length) {
      continue;
    }
    final stem = surface.substring(0, surface.length - pronoun.length);
    yield stem;
    final unaccented = _stripAccents(stem);
    if (unaccented != stem) {
      yield unaccented;
    }
  }
}

/// Resolves an enclitic cluster to `(lemma, pos)`, or `null`.
///
/// **A verb reading always wins, and a non-verb match is refused outright.**
/// Only verbs take enclitic pronouns, so when `dámelo` also matches the proper
/// noun *Dame*, the noun is not merely less likely — it is wrong. Carding it
/// would produce a bad card that still passes a "gloss is non-empty" check,
/// which is exactly the class of defect this guard exists for.
({String lemma, String pos})? resolveEnclitic(
  String surface,
  List<({String lemma, String pos})> Function(String stem) lookup,
) {
  for (final stem in splitEnclitics(surface)) {
    for (final row in lookup(stem)) {
      if (row.pos == 'verb') {
        return row;
      }
    }
  }
  return null;
}

String _stripAccents(String value) {
  const accented = 'áéíóúü';
  const plain = 'aeiouu';
  var result = value;
  for (var i = 0; i < accented.length; i++) {
    result = result.replaceAll(accented[i], plain[i]);
  }
  return result;
}
