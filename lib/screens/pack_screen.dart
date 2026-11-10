import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:lyricanki/services/attributions.dart';
import 'package:lyricanki/services/pack/pack_store.dart';

/// Downloads the dictionary pack and links the licence attribution.
///
/// The attribution is not decoration: the pack is built from Wiktionary data
/// via kaikki.org under **CC BY-SA**, which requires crediting the source and
/// naming the licence. See `attributions.dart`.
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
      appBar: AppBar(
        title: const Icon(
          Icons.storage_outlined,
          semanticLabel: 'Dictionary pack',
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Two tiles side by side: what the pack is, and what to do next.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(child: _statusTile(theme)),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: _actionTile()),
                ],
              ),
            ),
            if (_busy) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              LinearProgressIndicator(value: _progress),
            ],
            if (_error != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              // The cause is spoken only; on screen the offline glyph in the
              // error colour sits under a download button that is live again.
              Icon(
                Icons.cloud_off_outlined,
                key: const Key('pack-error'),
                color: theme.colorScheme.error,
                semanticLabel: _error,
              ),
            ],
            const Spacer(),
            const Align(
              alignment: Alignment.centerLeft,
              child: _CreditsButton(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusTile(ThemeData theme) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            _installed ? Icons.check_circle_outline : Icons.download_outlined,
            color: _installed ? theme.colorScheme.primary : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(widget.language, style: theme.textTheme.titleSmall),
        ],
      ),
    ),
  );

  Widget _actionTile() => Card(
    margin: EdgeInsets.zero,
    child: Center(
      child: _installed
          ? OutlinedButton(
              key: const Key('pack-remove'),
              onPressed: _busy ? null : _delete,
              child: const Icon(
                Icons.delete_outline,
                semanticLabel: 'Remove pack',
              ),
            )
          : FilledButton(
              key: const Key('pack-download'),
              onPressed: _busy ? null : _download,
              child: const Icon(
                Icons.download_outlined,
                semanticLabel: 'Download pack',
              ),
            ),
    ),
  );
}

/// Opens the licence notices the pack and lyrics sources require.
///
/// A tap on the (c) glyph is the ask: the notices sit in Flutter's licence
/// page next to every package's licence, registered by
/// [registerAttributions], instead of three paragraphs on every visit.
class _CreditsButton extends StatelessWidget {
  const _CreditsButton();

  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('pack-credits'),
    icon: const Icon(Icons.copyright, semanticLabel: 'Credits'),
    onPressed: () {
      registerAttributions();
      showLicensePage(context: context);
    },
  );
}
