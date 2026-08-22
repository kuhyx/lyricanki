import 'dart:io';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:lyricanki/models/export_entry.dart';
import 'package:lyricanki/models/vocab_card.dart';
import 'package:lyricanki/widgets/vocab_card_tile.dart';

/// What one exported song looks like up close: its stats, and what can be
/// done with it.
///
/// **No training state.** Reviewing happens inside AnkiDroid, in AnkiDroid's
/// own collection, which this app has no read access to -- it hands over an
/// `.apkg` through a share sheet and never hears about it again. A "cards
/// reviewed" figure here could only ever be blank or wrong, so the screen
/// shows what lyricanki actually owns.
class ExportDetailScreen extends StatelessWidget {
  /// Creates the screen.
  const ExportDetailScreen({
    required this.entry,
    required this.onShare,
    required this.onRebuild,
    required this.onHide,
    this.packReady = true,
    this.fileExists = _defaultFileExists,
    this.derivedCards,
    this.derivedUnresolved = const <String>[],
    super.key,
  });

  /// The entry being shown.
  final ExportEntry entry;

  /// Hands the existing `.apkg` to another app. Null-safe to call when the
  /// file is gone; the button is hidden in that case.
  final Future<void> Function() onShare;

  /// Rebuilds the deck from the stored lyrics, exactly as the first build did.
  final Future<void> Function() onRebuild;

  /// Hides this row from the list, leaving the file and the record alone.
  final Future<void> Function() onHide;

  /// Whether the dictionary pack is present.
  ///
  /// Rebuilding needs it, so without a pack the button is disabled with a
  /// reason rather than failing at tap time.
  final bool packReady;

  /// Whether the `.apkg` is still on disk. Injectable for tests.
  final bool Function(String) fileExists;

  /// Cards rebuilt from the stored lyrics, for entries exported before the
  /// deck was recorded.
  ///
  /// Null when the dictionary pack is unavailable, which is the one case
  /// where an old entry can show no word list at all. Never used when the
  /// entry carries its own cards -- those are what actually shipped.
  final List<VocabCard>? derivedCards;

  /// Unresolved surfaces from the same rebuild. See [derivedCards].
  final List<String> derivedUnresolved;

  /// The cards to show, and whether they are the exported ones.
  ///
  /// Stored cards are the record of what shipped. Derived ones are a best
  /// effort for older entries and are labelled as such, because unticked
  /// words and pack updates both make them differ from the real deck.
  bool get _hasStoredCards => entry.cards.isNotEmpty;

  List<VocabCard> get _cards =>
      _hasStoredCards ? entry.cards : (derivedCards ?? const <VocabCard>[]);

  List<String> get _unresolved =>
      _hasStoredCards ? entry.unresolved : derivedUnresolved;

  static bool _defaultFileExists(String path) => File(path).existsSync();

  @override
  Widget build(BuildContext context) {
    final missing = !fileExists(entry.path);
    return Scaffold(
      appBar: AppBar(
        title: Text(entry.name),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.visibility_off_outlined),
            tooltip: 'Hide from list',
            onPressed: () => _confirmHide(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: <Widget>[
          _Stat(label: 'Artist', value: entry.artist),
          _Stat(label: 'Cards', value: '${entry.cardCount}'),
          _Stat(label: 'Words in lyrics', value: '${_wordCount(entry.lyrics)}'),
          _Stat(label: 'Exported', value: _formatDateTime(entry.exportedAt)),
          _Stat(
            label: 'File',
            value: missing ? 'Removed' : entry.path,
          ),
          const SizedBox(height: AppSpacing.lg),
          if (!missing)
            FilledButton.icon(
              onPressed: onShare,
              icon: const Icon(Icons.share_outlined),
              label: const Text('Open in AnkiDroid'),
            ),
          if (!missing) const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: packReady ? onRebuild : null,
            icon: const Icon(Icons.refresh),
            label: Text(missing ? 'Rebuild deck' : 'Rebuild from lyrics'),
          ),
          if (!packReady)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                'Download the dictionary pack to rebuild this deck.',
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          WordListHeader(
            count: _cards.length,
            exact: _hasStoredCards,
            cardCount: entry.cardCount,
            empty: _cards.isEmpty,
          ),
          // The same tile the review screen ticks before export, so this list
          // reads identically to the one that was approved.
          for (final card in _cards) VocabCardTile(card: card),
          UnresolvedWordsNote(unresolved: _unresolved),
        ],
      ),
    );
  }

  Future<void> _confirmHide(BuildContext context) async {
    // Captured before any await. `Navigator.of(context)` afterwards depends
    // on the element still being mounted, and the write in between is real
    // filesystem work -- so the lookup can fail exactly when the pop matters.
    final navigator = Navigator.of(context);
    final confirmed = await confirmDestructive(
      context,
      title: 'Hide this song?',
      message:
          'It disappears from the list. The exported file is kept, and '
          'exporting the song again brings the row back.',
      confirmLabel: 'Hide',
    );
    if (!confirmed) return;
    await onHide();
    // The screen dismisses itself: popping from the caller's context reaches
    // into this route from outside it, which is fragile and lands a frame
    // later than the user expects.
    navigator.pop();
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: theme.textTheme.labelMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(value, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}

/// Whitespace-separated tokens, which is what "how many words" means to
/// someone looking at a lyric sheet -- not the deduplicated lemma count the
/// deck is built from, which is already shown as "Cards".
int _wordCount(String lyrics) =>
    lyrics.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

String _formatDateTime(DateTime at) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${at.year}-${two(at.month)}-${two(at.day)} '
      '${two(at.hour)}:${two(at.minute)}';
}
