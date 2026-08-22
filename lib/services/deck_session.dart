import 'package:flutter/foundation.dart';
import 'package:lyricanki/models/track.dart';
import 'package:lyricanki/models/vocab_card.dart';
import 'package:lyricanki/services/apkg/apkg_writer.dart';
import 'package:lyricanki/services/pack/pack_reader.dart';
import 'package:lyricanki/services/pipeline/deck_builder.dart';

/// One card in the review list, with whether the user wants to export it.
@immutable
class ReviewEntry {
  /// Creates an entry.
  const ReviewEntry({required this.card, required this.selected});

  /// The card itself.
  final VocabCard card;

  /// Whether it is ticked for export.
  final bool selected;

  /// Returns a copy with [selected] flipped.
  ReviewEntry toggled() => ReviewEntry(card: card, selected: !selected);
}

/// Holds the state of turning one chosen track into a deck.
///
/// Everything starts **selected**: Q3 makes this a choice the user makes by
/// unticking, not a filter the app applies. Function words are cards too.
class DeckSession extends ChangeNotifier {
  /// Creates a session over [pack] for [languageCode].
  DeckSession({required this.pack, required this.languageCode});

  /// The dictionary pack in use.
  final PackReader pack;

  /// Language code, used for the tokenizer and the note guid key.
  final String languageCode;

  Track? _track;
  List<ReviewEntry> _entries = <ReviewEntry>[];
  List<String> _unresolved = <String>[];

  /// The track the deck is being built from, or `null` before one is chosen.
  Track? get track => _track;

  /// Every candidate card, in first-appearance order.
  List<ReviewEntry> get entries => List<ReviewEntry>.unmodifiable(_entries);

  /// Surfaces the pack could not resolve.
  ///
  /// Shown rather than hidden: on the pinned song these are all ad-libs and
  /// English loanwords, so a real Spanish word here means the pack regressed.
  List<String> get unresolved => List<String>.unmodifiable(_unresolved);

  /// The cards currently ticked for export.
  List<VocabCard> get selectedCards => <VocabCard>[
    for (final entry in _entries)
      if (entry.selected) entry.card,
  ];

  /// How many cards are ticked.
  int get selectedCount => selectedCards.length;

  /// Builds the draft for [track], replacing any previous one.
  void load(Track track) {
    _track = track;
    final draft = DeckBuilder(
      pack: pack,
      languageCode: languageCode,
    ).build(track.plainLyrics);
    _entries = <ReviewEntry>[
      for (final card in draft.cards) ReviewEntry(card: card, selected: true),
    ];
    _unresolved = draft.unresolved;
    notifyListeners();
  }

  /// Ticks or unticks the entry at [index].
  void toggle(int index) {
    _entries = <ReviewEntry>[
      for (var i = 0; i < _entries.length; i++)
        if (i == index) _entries[i].toggled() else _entries[i],
    ];
    notifyListeners();
  }

  /// Ticks every entry.
  void selectAll() => _setAll(selected: true);

  /// Unticks every entry.
  void selectNone() => _setAll(selected: false);

  void _setAll({required bool selected}) {
    _entries = <ReviewEntry>[
      for (final entry in _entries)
        ReviewEntry(card: entry.card, selected: selected),
    ];
    notifyListeners();
  }

  /// Writes the selected cards to [path] and returns the file's size.
  ///
  /// The deck is named after the track, so re-exporting the same song lands
  /// in the same Anki deck.
  Future<int> export(String path) async {
    final file = await ApkgWriter(language: languageCode).writeToFile(
      cards: selectedCards,
      deckName: _track?.name ?? 'lyricanki',
      path: path,
    );
    return file.length();
  }
}
