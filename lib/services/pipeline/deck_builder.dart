import 'package:lyricanki/models/vocab_card.dart';
import 'package:lyricanki/services/pack/pack_reader.dart';
import 'package:lyricanki/services/pipeline/tokenizer.dart';

/// The outcome of turning one song's lyrics into candidate cards.
class DeckDraft {
  /// Creates a draft.
  const DeckDraft({required this.cards, required this.unresolved});

  /// One card per unique lemma, in first-appearance order.
  final List<VocabCard> cards;

  /// Surfaces the pack could not resolve, in first-appearance order.
  ///
  /// Surfaced rather than swallowed: on the pinned track these are all
  /// non-Spanish (ad-libs and English loanwords), so a real Spanish word
  /// appearing here means the pack regressed.
  final List<String> unresolved;
}

/// Turns lyrics into a deck draft using a dictionary pack.
class DeckBuilder {
  /// Creates a builder over [pack] for [languageCode].
  DeckBuilder({required this.pack, required String languageCode})
    : _tokenizer = Tokenizer.forLanguage(languageCode);

  /// The dictionary pack to resolve against.
  final PackReader pack;

  final Tokenizer _tokenizer;

  /// Builds the draft for [lyrics].
  ///
  /// **One card per unique lemma, not per surface form and not per part of
  /// speech.** `está` and `estás` both resolve to *estar* and yield a single
  /// card — that collapse is why the card count is far below the 183 surface
  /// forms.
  ///
  /// A lemma that resolves under several parts of speech also gets **one**
  /// card, carrying every reading. Q19 keys the Anki guid on `es|<lemma>`, so
  /// two notes for one lemma would collide into one on import anyway and the
  /// second reading would be lost silently; merging keeps both. `tu` in the
  /// pinned song is exactly this — a determiner and an adjective, both
  /// meaning "your" — and the merged card shows `your` once rather than
  /// shipping two identical-looking cards.
  ///
  /// Every lemma is kept, function words included: Q3 makes inclusion the
  /// user's choice on the review screen, not a filter applied here.
  DeckDraft build(String lyrics) {
    final byLemma = <String, VocabCard>{};
    final unresolved = <String>[];
    _tokenizer.uniqueSurfaces(lyrics).forEach((surface, line) {
      final card = pack.cardFor(surface, line.text);
      if (card == null) {
        unresolved.add(surface);
        return;
      }
      final existing = byLemma[card.lemma];
      // First occurrence wins for the context line: that is the line the
      // learner met the word in. Later readings only contribute pos and gloss.
      byLemma[card.lemma] = existing == null ? card : existing.mergedWith(card);
    });
    return DeckDraft(
      cards: byLemma.values.toList(),
      unresolved: unresolved,
    );
  }
}
