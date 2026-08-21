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
  /// requires zero notes whose gloss is empty.
  final String gloss;

  /// The lyric line the word was met in, kept as the card's context.
  final String line;

  /// Combines this card with [other], which must share its lemma.
  ///
  /// A lemma can resolve under several parts of speech — `tu` is both a
  /// determiner and an adjective — and Q19 gives one Anki note per lemma, so
  /// the readings have to travel on one card or the later one is lost. Parts
  /// of speech are joined with `/` and glosses with `; `, each de-duplicated:
  /// both of `tu`'s readings gloss as "your", and repeating it would make the
  /// merge look like a bug on the card.
  ///
  /// The context [line] is kept from this card, which is the first occurrence.
  VocabCard mergedWith(VocabCard other) {
    assert(other.lemma == lemma, 'can only merge readings of the same lemma');
    return VocabCard(
      lemma: lemma,
      pos: _join(<String>[pos, other.pos], '/'),
      gloss: _join(<String>[gloss, other.gloss], '; '),
      line: line,
    );
  }

  /// Joins [parts] with [separator], dropping blanks and duplicates.
  static String _join(List<String> parts, String separator) {
    final seen = <String>{};
    final kept = <String>[];
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      if (seen.add(trimmed.toLowerCase())) kept.add(trimmed);
    }
    return kept.join(separator);
  }

  /// Whether this card is fit to export.
  ///
  /// The bar is a **non-empty gloss**, and deliberately nothing more.
  ///
  /// An earlier version also rejected a gloss equal to the word, aiming at the
  /// defect that produced cards reading "Corazón." for *corazón*. That test
  /// was wrong twice over. It is aimed at the wrong layer: those glosses came
  /// from the per-language extract, which defines Spanish words in Spanish,
  /// and `tools/pack_builder` already refuses to let that source populate
  /// `gloss_en` at all. And it destroys real cards — Spanish and English share
  /// plenty of homographs, so `me` really is glossed "me" and `metal` really
  /// is glossed "metal". Both are correct translations a learner still needs;
  /// dropping them to catch a bug that is fixed elsewhere loses information
  /// for nothing.
  ///
  /// Punctuation-only and whitespace-only glosses are still rejected, since
  /// those carry no translation at all.
  bool get isExportable => _normalise(gloss).isNotEmpty;

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
