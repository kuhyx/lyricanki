import 'package:design_system/design_system.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lyricanki/services/deck_session.dart';
import 'package:lyricanki/widgets/vocab_card_cell.dart';
import 'package:lyricanki/widgets/vocab_card_tile.dart';

/// Lists every candidate card and lets the user untick the ones they know.
///
/// Q3: every unique lemma is a card, function words included, and everything
/// starts ticked. This screen is a **choice**, not a filter — the app never
/// decides a word is too common to be worth learning.
class ReviewScreen extends StatefulWidget {
  /// Creates the review screen.
  const ReviewScreen({
    required this.session,
    required this.onExport,
    super.key,
  });

  /// The session holding the draft.
  final DeckSession session;

  /// Called when the user exports; returns a message to show.
  final Future<String> Function() onExport;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  bool _exporting = false;

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final message = await widget.onExport();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        final entries = session.entries;
        return Scaffold(
          appBar: AppBar(
            title: Text(session.track?.name ?? 'Review'),
            actions: <Widget>[
              TextButton(
                onPressed: session.selectAll,
                child: const Text('All'),
              ),
              TextButton(
                onPressed: session.selectNone,
                child: const Text('None'),
              ),
            ],
          ),
          body: entries.isEmpty
              ? const EmptyState(
                  icon: Icons.translate_outlined,
                  title: 'No words yet',
                  message: 'Pick a song to build a deck from it.',
                )
              // Desktop ignores mouse drags by default; without this the
              // Linux build could not leave page 1 of the deck.
              : ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: PointerDeviceKind.values.toSet(),
                  ),
                  child: FitGrid(
                    itemCount: entries.length,
                    minSquare: 0.8,
                    itemBuilder: (context, index) => VocabCardCell(
                      key: ValueKey<String>('cell-$index'),
                      card: entries[index].card,
                      selected: entries[index].selected,
                      onToggle: () => session.toggle(index),
                    ),
                  ),
                ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (session.unresolved.isNotEmpty)
                    // Surfaced, not dropped: the canary for a pack regression.
                    TextButton(
                      onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        showDragHandle: true,
                        // Full width like the card sheet: on device the
                        // sheet otherwise shrank to its text, half the screen.
                        builder: (_) => SafeArea(
                          child: SizedBox(
                            width: double.infinity,
                            child: UnresolvedWordsNote(
                              unresolved: session.unresolved,
                            ),
                          ),
                        ),
                      ),
                      child: Text(
                        '${session.unresolved.length} words not in the '
                        'dictionary',
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: _exporting || session.selectedCount == 0
                        ? null
                        : _export,
                    icon: _exporting
                        ? const SizedBox.square(
                            dimension: AppSpacing.md,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_outlined),
                    label: Text(
                      _exporting
                          ? 'Exporting…'
                          : 'Export ${session.selectedCount} cards',
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
