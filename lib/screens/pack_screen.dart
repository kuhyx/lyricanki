import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:lyricanki/services/pack/pack_store.dart';

/// Downloads the dictionary pack and carries the licence attribution.
///
/// The attribution is not decoration: the pack is built from Wiktionary data
/// via kaikki.org under **CC BY-SA**, which requires crediting the source and
/// naming the licence. LRCLIB is credited because the lyrics come from there.
class PackScreen extends StatefulWidget {
  /// Creates the pack screen.
  const PackScreen({
    required this.store,
    required this.language,
    this.onChanged,
    super.key,
  });

  /// Store that owns pack files.
  final PackStore store;

  /// Language code of the pack this screen manages.
  final String language;

  /// Called after a pack is installed or removed.
  final VoidCallback? onChanged;

  @override
  State<PackScreen> createState() => _PackScreenState();
}

class _PackScreenState extends State<PackScreen> {
  bool _installed = false;
  bool _busy = false;
  double? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final installed = await widget.store.hasPack(widget.language);
    if (!mounted) return;
    setState(() => _installed = installed);
  }

  Future<void> _download() async {
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
    });
    try {
      await widget.store.download(
        widget.language,
        onProgress: (fraction) {
          if (mounted) setState(() => _progress = fraction);
        },
      );
      await _refresh();
      widget.onChanged?.call();
    } on PackDownloadException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _delete() async {
    await widget.store.delete(widget.language);
    await _refresh();
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Dictionary pack')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: <Widget>[
          ListTile(
            leading: Icon(
              _installed ? Icons.check_circle_outline : Icons.download_outlined,
            ),
            title: Text('Spanish (${widget.language})'),
            subtitle: Text(
              _installed
                  ? 'Installed. Words resolve offline.'
                  : 'Not installed. About 43 MB.',
            ),
          ),
          if (_busy) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            LinearProgressIndicator(value: _progress),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          if (_installed)
            OutlinedButton.icon(
              onPressed: _busy ? null : _delete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Remove pack'),
            )
          else
            FilledButton.icon(
              onPressed: _busy ? null : _download,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Download pack'),
            ),
          const SizedBox(height: AppSpacing.xl),
          const _Attribution(),
        ],
      ),
    );
  }
}

/// The licence notices the pack and lyrics sources require.
class _Attribution extends StatelessWidget {
  const _Attribution();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Credits', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Dictionary data from Wiktionary via kaikki.org, used under '
          'CC BY-SA 4.0 and the GFDL. Definitions fetched online come from '
          'English Wiktionary under CC BY-SA 3.0 and the GFDL.',
          style: muted,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text('Lyrics from LRCLIB (lrclib.net).', style: muted),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Decks are generated on this device for personal study. Lyrics are '
          'never stored or shared by this app.',
          style: muted,
        ),
      ],
    );
  }
}
