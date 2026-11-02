import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:lyricanki/models/vocab_card.dart';
import 'package:lyricanki/widgets/vocab_card_tile.dart';

/// One card as a compact grid cell on the review screen.
///
/// Tap ticks or unticks it; long-press opens the full card (gloss and the
/// lyric line) in a sheet, so the secondary detail is one gesture away
/// rather than dropped to make the grid fit.
class VocabCardCell extends StatelessWidget {
  /// Creates a cell for [card].
  const VocabCardCell({
    required this.card,
    required this.selected,
    required this.onToggle,
    super.key,
  });

  /// The card to show.
  final VocabCard card;

  /// Whether the card is ticked for export.
  final bool selected;

  /// Called when the cell is tapped.
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      checked: selected,
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onToggle,
          onLongPress: () => showCardDetail(context, card),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        card.lemma,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    Icon(
                      selected
                          ? Icons.check_box_outlined
                          : Icons.check_box_outline_blank,
                      size: AppSpacing.lg,
                    ),
                  ],
                ),
                Text(
                  card.pos,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall,
                ),
                Expanded(
                  child: Text(
                    card.gloss,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens [card] in full, in the same layout the export detail uses.
Future<void> showCardDetail(BuildContext context, VocabCard card) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(child: VocabCardTile(card: card)),
    );
