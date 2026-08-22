import 'package:lyricanki/models/track.dart';

/// The song the bug was reported against, used wherever a real track is
/// needed. Its id is LRCLIB's, so it doubles as the history record's id.
const Track despacito = Track(
  id: 36856755,
  name: 'Despacito',
  artist: 'Luis Fonsi',
  durationSeconds: 273,
  plainLyrics: 'Sí, sabes que ya llevo un rato mirándote',
);

/// A second track, so "keeps different tracks apart" means something.
const Track bailando = Track(
  id: 12345678,
  name: 'Bailando',
  artist: 'Enrique Iglesias',
  durationSeconds: 245,
  plainLyrics: 'Yo te miro y se me corta la respiración',
);
