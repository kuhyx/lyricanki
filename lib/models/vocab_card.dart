import 'package:meta/meta.dart';

/// One exportable card: a lemma with everything the Anki note needs.
///
/// The four fields map one-to-one onto the note type's fields
/// (`Word` / `POS` / `Gloss` / `Line`) in that order.
@immutable
class VocabCard {
  /// Creates a card.
  const VocabCard({
    required this.lemma,
    required this.pos,
    required this.gloss,
    required this.line,
  });

  /// The dictionary form, e.g. `corazón`. This is the note's first field, so
  /// it is what the guid and the duplicate checksum are computed from.
  final String lemma;

  /// Part of speech as the pack records it, e.g. `noun`.
  final String pos;

  /// English gloss. Never empty on an exported card: the done condition
  /// requires zero notes whose gloss is empty or equal to the word.
  final String gloss;

  /// The lyric line the word was met in, kept as the card's context.
  final String line;

  /// Whether this card is fit to export.
  ///
  /// A gloss equal to the word is the signature of the bug that produced cards
  /// reading "Corazón." for *corazón* — the per-language extract defines
  /// Spanish words in Spanish. Such a card teaches nothing, and it passes a
  /// naive "gloss is non-empty" check, so it is rejected explicitly here.
  ///
  /// The comparison ignores case and surrounding punctuation, because the real
  /// defect arrived as `"Corazón."` — capitalised and full-stopped, so a plain
  /// `gloss != lemma` test lets it straight through.
  bool get isExportable {
    final cleanedGloss = _normalise(gloss);
    if (cleanedGloss.isEmpty) return false;
    return cleanedGloss != _normalise(lemma);
  }

  /// Lowercases and strips surrounding whitespace and punctuation.
  static String _normalise(String value) =>
      value.trim().toLowerCase().replaceAll(_edgePunctuation, '');

  static final RegExp _edgePunctuation = RegExp(
    r'''^[\s.,;:!¡?¿"']+|[\s.,;:!¡?¿"']+$''',
  );

  @override
  bool operator ==(Object other) =>
      other is VocabCard &&
      other.lemma == lemma &&
      other.pos == pos &&
      other.gloss == gloss &&
      other.line == line;

  @override
  int get hashCode => Object.hash(lemma, pos, gloss, line);

  @override
  String toString() => 'VocabCard($lemma, $pos)';
}
