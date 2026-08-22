import 'package:flutter/material.dart';
import 'package:lyricanki/models/track.dart';
import 'package:lyricanki/screens/review_screen.dart';
import 'package:lyricanki/services/deck_session.dart';
import 'package:lyricanki/services/pack/pack_reader.dart';

/// Builds a deck for [track] and shows the review screen for it.
///
/// Split out of `SongSearchScreen` when the history list landed: the screen
/// was near the repo's 250-line cap, and this is the part with no dependency
/// on the screen's own state -- it needs a pack, a track and somewhere to
/// send the finished deck.
///
/// [onExport] is invoked from the review screen's export button and returns
/// the status line to show. The pack is closed on the way out, including when
/// the user backs out without exporting.
Future<void> pushReview({
  required BuildContext context,
  required String packPath,
  required String languageCode,
  required Track track,
  required Future<String> Function(DeckSession, Track) onExport,
}) async {
  final session = DeckSession(
    pack: PackReader.open(packPath),
    languageCode: languageCode,
  )..load(track);
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => ReviewScreen(
        session: session,
        onExport: () => onExport(session, track),
      ),
    ),
  );
  session.pack.close();
}
