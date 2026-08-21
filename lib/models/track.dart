import 'package:meta/meta.dart';

/// One LRCLIB search result.
@immutable
class Track {
  /// Creates a track.
  const Track({
    required this.id,
    required this.name,
    required this.artist,
    required this.durationSeconds,
    required this.plainLyrics,
  });

  /// Builds a track from an LRCLIB API object.
  ///
  /// LRCLIB returns `null` for `plainLyrics` on instrumental tracks and on
  /// entries that only carry synced lyrics, so it is normalised to `''` here
  /// rather than left nullable for every caller to re-check.
  factory Track.fromJson(Map<String, dynamic> json) {
    final duration = json['duration'];
    return Track(
      id: json['id'] as int,
      name: (json['trackName'] as String?) ?? '',
      artist: (json['artistName'] as String?) ?? '',
      durationSeconds: duration is num ? duration.round() : 0,
      plainLyrics: (json['plainLyrics'] as String?) ?? '',
    );
  }

  /// LRCLIB's track id. This is what gets pinned: a bare "Despacito" search
  /// returns the Bieber remix too, which has English verses.
  final int id;

  /// Track title.
  final String name;

  /// Performing artist.
  final String artist;

  /// Duration in seconds, used to tell versions apart in the picker.
  final int durationSeconds;

  /// Unsynced lyrics, or `''` when LRCLIB has none.
  final String plainLyrics;

  /// Whether this track carries lyrics that can be turned into a deck.
  bool get hasLyrics => plainLyrics.trim().isNotEmpty;

  /// Duration rendered as `m:ss`, the form the picker shows.
  String get durationLabel {
    final minutes = durationSeconds ~/ 60;
    final seconds = (durationSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  bool operator ==(Object other) => other is Track && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Track($id, $name)';
}
