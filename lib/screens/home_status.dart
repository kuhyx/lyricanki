import 'package:flutter/material.dart';

/// What the home screen's last background action came to.
enum HomeStatusKind {
  /// A sync is running.
  syncing,

  /// A sync finished; [HomeStatus.count] songs are in the merged history.
  synced,

  /// A sync or a lyrics fetch failed; [HomeStatus.detail] says why.
  failed,
}

/// A home-screen status as state rather than a sentence.
///
/// Replaced the old status line ("Syncing...", "Synced -- 4 songs.", "Sync
/// failed: ..."): kuhy's textgate rule allows no painted chrome words, so the
/// app bar shows [HomeStatusGlyph] and the cause is spoken only.
@immutable
class HomeStatus {
  /// Creates a status of [kind].
  const HomeStatus(this.kind, {this.count, this.detail});

  /// Which outcome this is.
  final HomeStatusKind kind;

  /// Songs merged, for [HomeStatusKind.synced].
  final int? count;

  /// The cause, for [HomeStatusKind.failed]. Spoken, never painted.
  final String? detail;
}

/// The app-bar glyph for a [HomeStatus].
///
/// Spinner while syncing; cloud-done in the primary colour plus the merged
/// count; cloud-off in the error colour on a failure. Second channel to the
/// colour is the glyph shape, so no state rests on colour alone.
class HomeStatusGlyph extends StatelessWidget {
  /// Creates the glyph for [status].
  const HomeStatusGlyph({required this.status, super.key});

  /// The status to show.
  final HomeStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: switch (status.kind) {
        HomeStatusKind.syncing => const SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        HomeStatusKind.synced => Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.cloud_done_outlined,
              color: scheme.primary,
              semanticLabel: 'Synced',
            ),
            const SizedBox(width: 4),
            Text('${status.count ?? 0}'),
          ],
        ),
        HomeStatusKind.failed => Icon(
          Icons.cloud_off_outlined,
          color: scheme.error,
          semanticLabel: status.detail,
        ),
      },
    );
  }
}
