import 'dart:async';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:lyricanki/models/track.dart';
import 'package:lyricanki/screens/pack_screen.dart';
import 'package:lyricanki/screens/review_screen.dart';
import 'package:lyricanki/screens/track_picker_screen.dart';
import 'package:lyricanki/services/deck_session.dart';
import 'package:lyricanki/services/lrclib_client.dart';
import 'package:lyricanki/services/pack/pack_reader.dart';
import 'package:lyricanki/services/pack/pack_store.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Entry screen: check the pack is present, find a song, build a deck.
class SongSearchScreen extends StatefulWidget {
  /// Creates the screen.
  const SongSearchScreen({
    this.client,
    this.store,
    this.language = 'es',
    super.key,
  });

  /// LRCLIB client; constructed when omitted.
  final LrclibClient? client;

  /// Pack store; constructed when omitted.
  final PackStore? store;

  /// Language to build decks for.
  final String language;

  @override
  State<SongSearchScreen> createState() => _SongSearchScreenState();
}

class _SongSearchScreenState extends State<SongSearchScreen> {
  late final LrclibClient _client = widget.client ?? LrclibClient();
  late final PackStore _store = widget.store ?? PackStore();
  bool _packReady = false;
  bool _working = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshPack());
  }

  @override
  void dispose() {
    _client.close();
    _store.close();
    super.dispose();
  }

  Future<void> _refreshPack() async {
    final ready = await _store.hasPack(widget.language);
    if (!mounted) return;
    setState(() => _packReady = ready);
  }

  Future<void> _openPackScreen() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PackScreen(store: _store, language: widget.language),
      ),
    );
    await _refreshPack();
  }

  Future<void> _pickAndBuild() async {
    final track = await Navigator.of(context).push<Track>(
      MaterialPageRoute<Track>(
        builder: (_) => TrackPickerScreen(client: _client),
      ),
    );
    if (track == null || !mounted) return;
    setState(() {
      _working = true;
      _status = null;
    });
    try {
      // Lyrics come back empty from search on some rows, so the chosen track
      // is always re-fetched by id before its words are counted.
      final full = await _client.getById(track.id);
      final packPath = (await _store.packFile(widget.language)).path;
      final session = DeckSession(
        pack: PackReader.open(packPath),
        languageCode: widget.language,
      )..load(full);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ReviewScreen(
            session: session,
            onExport: () => _export(session, full),
          ),
        ),
      );
      session.pack.close();
    } on LrclibException catch (error) {
      if (mounted) setState(() => _status = error.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<String> _export(DeckSession session, Track track) async {
    final dir = await getApplicationDocumentsDirectory();
    final name = track.name.replaceAll(RegExp('[^A-Za-z0-9]+'), '_');
    final path = p.join(dir.path, '$name.apkg');
    final bytes = await session.export(path);
    return 'Exported ${session.selectedCount} cards '
        '(${(bytes / 1024).round()} KB) to $path';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('lyricanki'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.storage_outlined),
            tooltip: 'Dictionary pack',
            onPressed: _openPackScreen,
          ),
        ],
      ),
      body: _working
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: _packReady
                  ? EmptyState(
                      icon: Icons.library_music_outlined,
                      title: 'Ready',
                      message:
                          _status ??
                          'Search for a song to build a vocabulary deck '
                              'from every word in it.',
                    )
                  : const EmptyState(
                      icon: Icons.storage_outlined,
                      title: 'No dictionary yet',
                      message:
                          'Download the dictionary pack before building a '
                          'deck. Tap the storage icon above.',
                    ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _packReady && !_working ? _pickAndBuild : null,
        icon: const Icon(Icons.search),
        label: const Text('Find a song'),
      ),
    );
  }
}
