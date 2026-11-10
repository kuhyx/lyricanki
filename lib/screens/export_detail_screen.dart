import 'dart:io';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:lyricanki/models/export_entry.dart';
import 'package:lyricanki/models/vocab_card.dart';
import 'package:lyricanki/widgets/icon_confirm.dart';
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
            icon: const Icon(
              Icons.visibility_off_outlined,
              semanticLabel: 'Hide from list',
            ),
            onPressed: () => _confirmHide(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: <Widget>[
          _Stat(
            icon: Icons.person_outline,
            value: entry.artist,
            semanticLabel: 'Artist',
          ),
          _Stat(
            icon: Icons.style_outlined,
            value: '${entry.cardCount}',
            semanticLabel: 'Cards',
          ),
          _Stat(
            icon: Icons.notes,
            value: '${_wordCount(entry.lyrics)}',
            semanticLabel: 'Words in lyrics',
          ),
          _Stat(
            icon: Icons.event_outlined,
            value: _formatDateTime(entry.exportedAt),
            semanticLabel: 'Exported',
          ),
          _Stat(
            icon: missing
                ? Icons.delete_outline
                : Icons.insert_drive_file_outlined,
            value: missing ? '' : entry.path,
            semanticLabel: missing ? 'Removed' : 'File',
            iconColor: missing ? Theme.of(context).colorScheme.error : null,
          ),
          const SizedBox(height: AppSpacing.lg),
          if (!missing)
            FilledButton(
              onPressed: onShare,
              child: const Icon(
                Icons.share_outlined,
                semanticLabel: 'Open in AnkiDroid',
              ),
            ),
          if (!missing) const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: packReady ? onRebuild : null,
            child: const Icon(Icons.refresh, semanticLabel: 'Rebuild'),
          ),
          if (!packReady)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Icon(
                Icons.storage_outlined,
                color: Theme.of(context).colorScheme.error,
                semanticLabel: 'Dictionary pack missing',
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
    final confirmed = await confirmByIcon(
      context,
      icon: Icons.visibility_off_outlined,
      semanticLabel: 'Hide from list',
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
  const _Stat({
    required this.icon,
    required this.value,
    required this.semanticLabel,
    this.iconColor,
  });

  final IconData icon;
  final String value;
  final String semanticLabel;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, semanticLabel: semanticLabel, color: iconColor, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SizedBox(height: 2),
                Text(value, style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
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
