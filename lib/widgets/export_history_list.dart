import 'dart:io';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:lyricanki/models/export_entry.dart';

/// The exported-song list that fills the home screen once anything exists.
///
/// Takes plain data and callbacks rather than the store, so it can be
/// exercised without a filesystem and reused from anywhere.
class ExportHistoryList extends StatelessWidget {
  /// Creates the list.
  const ExportHistoryList({
    required this.entries,
    required this.onOpen,
    this.fileExists = _defaultFileExists,
    super.key,
  });

  /// The rows to show, newest first. Never empty: the caller shows an
  /// [EmptyState] instead when there is no history.
  final List<ExportEntry> entries;

  /// Called when a row is tapped, with the entry it belongs to.
  final void Function(ExportEntry) onOpen;

  /// Whether the `.apkg` at a path is still on disk.
  ///
  /// Injectable so widget tests decide the answer without touching a real
  /// filesystem, which under `flutter test` would also be the wrong one.
  final bool Function(String) fileExists;

  static bool _defaultFileExists(String path) => File(path).existsSync();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl * 2),
      itemCount: entries.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return const SectionHeader(
            'Exported songs',
            padding: SectionHeader.defaultPadding,
          );
        }
        final entry = entries[index - 1];
        return _ExportRow(
          entry: entry,
          // The file is gone when Android clears external app storage, or
          // when the user deletes it. The row stays -- the export really
          // happened -- but it is shown as needing a rebuild rather than
          // silently vanishing.
          missing: !fileExists(entry.path),
          onTap: () => onOpen(entry),
        );
      },
    );
  }
}

class _ExportRow extends StatelessWidget {
  const _ExportRow({
    required this.entry,
    required this.missing,
    required this.onTap,
  });

  final ExportEntry entry;
  final bool missing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(
        missing ? Icons.help_outline : Icons.library_music_outlined,
        color: missing ? theme.disabledColor : null,
      ),
      title: Text(
        entry.label,
        style: missing
            ? theme.textTheme.bodyLarge?.copyWith(color: theme.disabledColor)
            : null,
      ),
      subtitle: Text(
        missing
            ? 'File removed — tap to rebuild'
            : '${entry.cardCount} cards · ${_formatDate(entry.exportedAt)}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// Renders a timestamp as `YYYY-MM-DD`.
///
/// Deliberately not a localized or relative format: the list is sorted newest
/// first, so the date is for telling two exports apart rather than for
/// reading as prose, and an absolute date never goes stale on screen.
String _formatDate(DateTime at) {
  final month = at.month.toString().padLeft(2, '0');
  final day = at.day.toString().padLeft(2, '0');
  return '${at.year}-$month-$day';
}

/// What the home screen shows below its app bar.
///
/// The list once anything has been exported, an empty state before that. The
/// reported bug was that a finished song left the home screen looking exactly
/// as it had before -- so the list, not a placeholder, is what a user with
/// history sees on open.
class HomeBody extends StatelessWidget {
  /// Creates the body.
  const HomeBody({
    required this.packReady,
    required this.entries,
    required this.onOpen,
    this.status,
    super.key,
  });

  /// Whether a dictionary pack is installed.
  final bool packReady;

  /// The visible history rows, newest first.
  final List<ExportEntry> entries;

  /// Opens one row.
  final void Function(ExportEntry) onOpen;

  /// A transient message (an export result, a sync outcome, an error).
  final String? status;

  @override
  Widget build(BuildContext context) {
    if (!packReady) {
      return const Center(
        child: EmptyState(
          icon: Icons.storage_outlined,
          title: 'No dictionary yet',
          message:
              'Download the dictionary pack before building a deck. '
              'Tap the storage icon above.',
        ),
      );
    }
    if (entries.isEmpty) {
      return Center(
        child: EmptyState(
          icon: Icons.library_music_outlined,
          title: 'Ready',
          message:
              status ??
              'Search for a song to build a vocabulary deck from every '
                  'word in it.',
        ),
      );
    }
    return ExportHistoryList(entries: entries, onOpen: onOpen);
  }
}
