/// Picking the right dictionary entry when a surface form matches several.
///
/// Wiktionary files proper nouns, initialisms and common words under the same
/// letters, so a naive "first row wins" turns the lyric `amor` into the
/// surname *Amor*, `me` into the initialism for "muerte encefálica", and `no`
/// into an abbreviation of *noroeste*. Each of those is a **wrong card that
/// still passes a "gloss is non-empty" check**, so the choice is made here
/// deliberately rather than left to row order.
///
/// This mirrors `tools/pack_builder/ranking.py`; the two must agree, or the
/// app's card count diverges from the builder's measurement.
library;

/// Parts of speech a lyric word is most likely to be, best first.
///
/// Function words outrank nouns because the words that repeat in a song are
/// overwhelmingly grammatical.
const List<String> posRank = <String>[
  'verb',
  'pron',
  'prep',
  'det',
  'article',
  'conj',
  'adv',
  'adj',
  'noun',
  'intj',
  'num',
];

/// Parts of speech that are almost never what a singer meant.
///
/// `character` is here because single letters (`D`, `Y`) are filed as
/// characters and would otherwise be carded as vocabulary.
const Set<String> posPenalty = <String>{
  'name',
  'abbrev',
  'symbol',
  'character',
  'punct',
  'phrase',
};

/// Spanish function words pinned to the sense a lyric actually uses.
///
/// Wiktionary lists rarer readings — `y` as a pronoun, `de` as a pronoun —
/// that win on POS rank alone, and the wrong reading is a wrong card. Pinning
/// the handful of words that carry a song is cheaper and far more accurate
/// than trying to rank POS generically.
const Map<String, String> functionWordPos = <String, String>{
  'y': 'conj',
  'o': 'conj',
  'de': 'prep',
  'a': 'prep',
  'en': 'prep',
  'con': 'prep',
  'por': 'prep',
  'para': 'prep',
  'sin': 'prep',
  'que': 'pron',
  'me': 'pron',
  'te': 'pron',
  'se': 'pron',
  'le': 'pron',
  'lo': 'pron',
  'la': 'article',
  'el': 'article',
  'un': 'article',
  'una': 'article',
  'mi': 'det',
  'tu': 'det',
  'su': 'det',
  'no': 'adv',
  'si': 'conj',
  'ya': 'adv',
  'mas': 'conj',
  'más': 'adv',
};

/// Returns a sort score for [pos]: lower is a better candidate.
int posScore(String pos) {
  if (posPenalty.contains(pos)) {
    return posRank.length + 10;
  }
  final index = posRank.indexOf(pos);
  return index == -1 ? posRank.length : index;
}

/// Orders [candidates] for [surface], best first.
///
/// A lowercase surface prefers a lowercase lemma: the singer wrote `amor`, not
/// the surname *Amor*. When [hasEnglish] is given, a candidate carrying an
/// English gloss outranks one that does not — the source holds non-Spanish
/// headwords under the same letters (`las` is also German *lesen*), and
/// picking those produced a card with no usable back.
List<({String lemma, String pos})> rankCandidates(
  String surface,
  List<({String lemma, String pos})> candidates, {
  bool Function(String lemma, String pos)? hasEnglish,
}) {
  final surfaceIsLower = surface == surface.toLowerCase();
  final pinned = functionWordPos[surface.toLowerCase()];

  int glossPenalty(({String lemma, String pos}) c) =>
      hasEnglish == null || hasEnglish(c.lemma, c.pos) ? 0 : 1;
  int casePenalty(({String lemma, String pos}) c) =>
      surfaceIsLower && c.lemma != c.lemma.toLowerCase() ? 1 : 0;
  int pinPenalty(({String lemma, String pos}) c) =>
      pinned != null && c.pos == pinned ? 0 : 1;

  final ranked = List<({String lemma, String pos})>.of(candidates)
    ..sort((a, b) {
      final byGloss = glossPenalty(a).compareTo(glossPenalty(b));
      if (byGloss != 0) return byGloss;
      final byCase = casePenalty(a).compareTo(casePenalty(b));
      if (byCase != 0) return byCase;
      final byPin = pinPenalty(a).compareTo(pinPenalty(b));
      if (byPin != 0) return byPin;
      final byPos = posScore(a.pos).compareTo(posScore(b.pos));
      if (byPos != 0) return byPos;
      return a.lemma.compareTo(b.lemma);
    });
  return ranked;
}

/// Returns the single best candidate for [surface], or `null` when empty.
({String lemma, String pos})? bestCandidate(
  String surface,
  List<({String lemma, String pos})> candidates, {
  bool Function(String lemma, String pos)? hasEnglish,
}) {
  if (candidates.isEmpty) return null;
  return rankCandidates(surface, candidates, hasEnglish: hasEnglish).first;
}
