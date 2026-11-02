import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:lyricanki/models/vocab_card.dart';

/// One card as a read-only row, rendered the same way everywhere it appears.
///
/// Shared by the export detail screen (afterwards, a record of what shipped)
/// and the review screen's long-press sheet, so a gloss or a context line
/// reads identically before and after the export.
class VocabCardTile extends StatelessWidget {
  /// Creates a tile for [card].
  const VocabCardTile({required this.card, super.key});

  /// The card to render. Its four fields are the Anki note's four fields.
  final VocabCard card;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text('${card.lemma}  ·  ${card.pos}'),
    subtitle: _Subtitle(card: card),
  );
}

/// The gloss, and the lyric line the word was met in.
///
/// Both are shown because together they are the whole answer to "how did this
/// word become a card": the gloss is the note's back, the line is its
/// context field.
class _Subtitle extends StatelessWidget {
  const _Subtitle({required this.card});

  final VocabCard card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(card.gloss, maxLines: 2, overflow: TextOverflow.ellipsis),
        if (card.line.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            card.line,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// Names the surfaces the dictionary pack could not resolve.
///
/// Shared for the same reason as [VocabCardTile]: "which words were dropped"
/// is half the answer to "what got exported", and it must read identically
/// before and after the export.
///
/// Surfaced rather than hidden -- on the pinned song every one is an ad-lib
/// or an English loanword, so a real Spanish word here means the pack
/// regressed.
class UnresolvedWordsNote extends StatelessWidget {
  /// Creates the note for [unresolved].
  const UnresolvedWordsNote({required this.unresolved, super.key});

  /// Surfaces with no dictionary entry, in first-appearance order.
  final List<String> unresolved;

  @override
  Widget build(BuildContext context) {
    if (unresolved.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${unresolved.length} words not in the dictionary',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            unresolved.join(', '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Introduces the word list, and says how far it can be trusted.
///
/// An entry exported before the deck was recorded has no stored cards, so the
/// list is rebuilt from the lyrics. That rebuild can differ from the real
/// deck -- unticked words are gone, and the dictionary pack may have changed
/// since -- and saying so is better than showing a count that quietly
/// disagrees with the "Cards" stat directly above it.
class WordListHeader extends StatelessWidget {
  /// Creates the header.
  const WordListHeader({
    required this.count,
    required this.exact,
    required this.cardCount,
    required this.empty,
    super.key,
  });

  /// How many words the list below holds.
  final int count;

  /// Whether those are the exported cards rather than a rebuild.
  final bool exact;

  /// How many cards the export actually shipped, per the record.
  final int cardCount;

  /// Whether there is no list to show at all.
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String note;
    if (empty) {
      note =
          'This song was exported before lyricanki recorded its words. '
          'Download the dictionary pack to rebuild the list.';
    } else if (exact) {
      note = 'The cards exactly as they were exported.';
    } else if (count != cardCount) {
      note =
          'Rebuilt from the lyrics -- $count words now, against $cardCount '
          'exported. They differ because words were unticked, or the '
          'dictionary has changed since.';
    } else {
      note =
          'Rebuilt from the lyrics, so it may differ from the exported deck.';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            empty ? 'Words' : 'Words ($count)',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            note,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
