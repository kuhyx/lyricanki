import 'package:flutter/material.dart';

/// Asks for confirmation with glyphs only; true when the user confirms.
///
/// Replaces `design_system`'s `confirmDestructive`, whose Cancel button is a
/// word. The dialog repeats the action's own [icon] large on top and on the
/// confirm button (error colour), next to a close glyph. Close is autofocused
/// so a reflexive Return backs out; Escape and the barrier dismiss as false.
Future<bool> confirmByIcon(
  BuildContext context, {
  required IconData icon,
  required String semanticLabel,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final scheme = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        icon: Icon(icon, color: scheme.error),
        actions: <Widget>[
          IconButton(
            key: const Key('confirm-cancel'),
            autofocus: true,
            icon: const Icon(Icons.close, semanticLabel: 'Cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          FilledButton(
            key: const Key('confirm-ok'),
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Icon(icon, semanticLabel: semanticLabel),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}
