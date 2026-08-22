import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:lyricanki/services/deck_session.dart';
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
              : ListView.builder(
                  itemCount: entries.length + 1,
                  itemBuilder: (context, index) {
                    if (index == entries.length) {
                      return UnresolvedWordsNote(
                        unresolved: session.unresolved,
                      );
                    }
                    final entry = entries[index];
                    // The same tile the export detail screen renders, so the
                    // list you approve looks like the list you exported.
                    return VocabCardTile(
                      card: entry.card,
                      selected: entry.selected,
                      onToggle: () => session.toggle(index),
                    );
                  },
                ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: FilledButton.icon(
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
            ),
          ),
        );
      },
    );
  }
}
