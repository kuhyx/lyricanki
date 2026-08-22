import 'package:flutter/material.dart';
import 'package:lyricanki/models/export_entry.dart';
import 'package:lyricanki/models/track.dart';
import 'package:lyricanki/screens/deck_flow.dart';
import 'package:lyricanki/screens/export_detail_screen.dart';
import 'package:lyricanki/screens/sync_screen.dart';
import 'package:lyricanki/services/deck_session.dart';
import 'package:lyricanki/services/export_history.dart';
import 'package:lyricanki/services/pipeline/deck_builder.dart';

/// The history half of the home screen: opening a row, hiding it, rebuilding
/// its deck.
///
/// A mixin rather than another widget because every one of these needs the
/// screen's own state (the pack, the share seam, the history store). Split
/// out purely for the repo's 250-line cap, which `song_search_screen.dart`
/// crossed when the list landed.
mixin SongSearchHistory<T extends StatefulWidget> on State<T> {
  /// The opened history, or null before it has loaded.
  ExportHistory? get history;

  /// Whether the dictionary pack is present; gates rebuilding.
  bool get packReady;

  /// The language decks are built for.
  String get languageCode;

  /// Path of the dictionary pack on disk.
  Future<String> packPath();

  /// Hands an `.apkg` to another app.
  Future<void> shareApkg(String path);

  /// Writes the deck and returns the status line, as a first export does.
  Future<String> exportSession(DeckSession session, Track track);

  /// Re-reads the visible rows after anything changes them.
  void refreshHistory();

  /// This install's sync id.
  String get deviceId;

  /// Merges the history with the other devices', or null when this device is
  /// not signed in.
  Future<int?> runSync(ExportHistory history, String deviceId);

  /// Shows [message] on the home screen.
  void showStatus(String message);

  /// Merges this device's history with every other device's.
  ///
  /// Manual by design: the list renders from the local log, so a network tick
  /// is never on the path that paints the home screen -- the reported bug
  /// cannot come back as a timeout.
  Future<void> syncNow() async {
    final store = history;
    if (store == null) return;
    showStatus('Syncing...');
    try {
      final count = await runSync(store, deviceId);
      if (!mounted) return;
      if (count == null) {
        // Not being set up is a normal state, not an error -- offer the way
        // in rather than reporting a failure.
        showStatus('Sync is not set up on this device.');
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(builder: (_) => const SyncScreen()),
        );
        return;
      }
      showStatus('Synced -- $count songs.');
      refreshHistory();
    } on Exception catch (error) {
      // Offline, or a rejected token. The local history is untouched and the
      // app keeps working, so this is a message rather than a crash.
      if (mounted) showStatus('Sync failed: $error');
    }
  }

  /// Opens the detail screen for [entry].
  Future<void> openEntry(ExportEntry entry) async {
    // Only for entries predating the stored deck: those have no word list
    // unless one is derived, and deriving needs the pack off disk.
    DeckDraft? derived;
    if (entry.cards.isEmpty && packReady) {
      final path = await packPath();
      if (!mounted) return;
      derived = draftFromLyrics(
        packPath: path,
        languageCode: languageCode,
        lyrics: entry.lyrics,
      );
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ExportDetailScreen(
          entry: entry,
          packReady: packReady,
          derivedCards: derived?.cards,
          derivedUnresolved: derived?.unresolved ?? const <String>[],
          onShare: () => shareApkg(entry.path),
          onRebuild: () => rebuild(entry),
          onHide: () => hide(entry),
        ),
      ),
    );
    refreshHistory();
  }

  /// Hides [entry]. The detail screen dismisses itself afterwards.
  Future<void> hide(ExportEntry entry) =>
      history?.setHidden(entry.trackId, hidden: true) ?? Future<void>.value();

  /// Rebuilds [entry]'s deck from the lyrics stored alongside it.
  ///
  /// Goes through the review screen exactly as a first build does, so the
  /// card selection is the user's again. Needs no network: the lyrics were
  /// kept when the song was first exported, precisely so a rebuild works
  /// offline and against a `.apkg` that is no longer on disk.
  Future<void> rebuild(ExportEntry entry) async {
    final path = await packPath();
    if (!mounted) return;
    // Leave the detail screen first, so backing out of the review screen
    // lands on the list rather than on a detail screen for a deck that has
    // just been rebuilt.
    Navigator.of(context).pop();
    await pushReview(
      context: context,
      packPath: path,
      languageCode: languageCode,
      track: Track(
        id: entry.trackId,
        name: entry.name,
        artist: entry.artist,
        // Unknown and unused: duration only tells versions apart in the
        // picker, and a rebuild never goes back through it.
        durationSeconds: 0,
        plainLyrics: entry.lyrics,
      ),
      onExport: exportSession,
    );
    refreshHistory();
  }
}
