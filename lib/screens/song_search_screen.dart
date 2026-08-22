import 'dart:async';
import 'package:crdt_sync_flutter/crdt_sync_flutter.dart';
import 'package:flutter/material.dart';
import 'package:lyricanki/models/export_entry.dart';
import 'package:lyricanki/models/track.dart';
import 'package:lyricanki/screens/deck_flow.dart';
import 'package:lyricanki/screens/pack_screen.dart';
import 'package:lyricanki/screens/song_search_history.dart';
import 'package:lyricanki/screens/track_picker_screen.dart';
import 'package:lyricanki/services/apkg_share.dart';
import 'package:lyricanki/services/deck_session.dart';
import 'package:lyricanki/services/export_destination.dart';
import 'package:lyricanki/services/export_history.dart';
import 'package:lyricanki/services/history_sync.dart';
import 'package:lyricanki/services/lrclib_client.dart';
import 'package:lyricanki/services/pack/pack_store.dart';
import 'package:lyricanki/widgets/export_history_list.dart';

/// Entry screen: check the pack is present, find a song, build a deck.
class SongSearchScreen extends StatefulWidget {
  /// Creates the screen.
  const SongSearchScreen({
    this.client,
    this.store,
    this.destination,
    this.share,
    this.history,
    this.syncHistory,
    this.language = 'es',
    super.key,
  });

  /// LRCLIB client; constructed when omitted.
  final LrclibClient? client;

  /// Pack store; constructed when omitted.
  final PackStore? store;

  /// Where exports are written; constructed when omitted.
  final ExportDestination? destination;

  /// Hands the finished deck to another app; constructed when omitted.
  final ApkgShare? share;

  /// The exported-song history; opened from the app support directory when
  /// omitted. Injected by tests so a run never touches the live history.
  final ExportHistory? history;

  /// Merges the history with the other devices'. Injected by tests, which
  /// must never reach the network or the OS keystore.
  final Future<int?> Function(ExportHistory, String)? syncHistory;

  /// Language to build decks for.
  final String language;

  @override
  State<SongSearchScreen> createState() => _SongSearchScreenState();
}

class _SongSearchScreenState extends State<SongSearchScreen>
    with SongSearchHistory<SongSearchScreen> {
  late final LrclibClient _client = widget.client ?? LrclibClient();
  late final PackStore _store = widget.store ?? PackStore();
  late final ExportDestination _destination =
      widget.destination ?? ExportDestination();
  late final ApkgShare _share = widget.share ?? ApkgShare();
  ExportHistory? _history;
  String _deviceId = '';
  List<ExportEntry> _entries = <ExportEntry>[];
  bool _packReady = false;
  bool _working = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshPack());
    unawaited(_openHistory());
  }

  @override
  void dispose() {
    _client.close();
    _store.close();
    super.dispose();
  }

  @override
  ExportHistory? get history => _history;

  @override
  bool get packReady => _packReady;

  @override
  String get languageCode => widget.language;

  @override
  Future<String> packPath() async =>
      (await _store.packFile(widget.language)).path;

  @override
  Future<void> shareApkg(String path) => _share.shareApkg(path);

  @override
  Future<String> exportSession(DeckSession session, Track track) =>
      _export(session, track);

  @override
  String get deviceId => _deviceId;

  @override
  Future<int?> runSync(ExportHistory store, String device) =>
      (widget.syncHistory ?? _defaultSync)(store, device);

  @override
  void showStatus(String message) => setState(() => _status = message);

  @override
  void refreshHistory() {
    final store = _history;
    if (store == null) return;
    setState(() => _entries = store.visible());
  }

  Future<void> _openHistory() async {
    // The device id is what the CRDT log stamps its writes with, so it is
    // resolved once here rather than per write.
    final deviceId = (await loadDeviceIdentity()).deviceId;
    final history =
        widget.history ?? await ExportHistory.open(deviceId: deviceId);
    if (!mounted) return;
    setState(() {
      _deviceId = deviceId;
      _history = history;
      _entries = history.visible();
    });
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
      final path = await packPath();
      if (!mounted) return;
      await pushReview(
        context: context,
        packPath: path,
        languageCode: widget.language,
        track: full,
        onExport: _export,
      );
    } on LrclibException catch (error) {
      if (mounted) setState(() => _status = error.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<String> _export(DeckSession session, Track track) async {
    final path = await _destination.pathFor(track.name);
    final bytes = await session.export(path);
    // Offer the file straight to AnkiDroid. Writing it and naming the path is
    // not enough on Android: from API 30 the storage picker cannot browse
    // into Android/data, so a user following the old message had no way to
    // reach the file they had just exported. AnkiDroid registers ACTION_SEND
    // for application/apkg, so the share sheet lands directly in its importer.
    // Recorded only now: doing it before the write would list a song whose
    // export then failed.
    await _history?.record(
      track: track,
      path: path,
      cardCount: session.selectedCount,
      // Exactly the cards that shipped, so the detail screen shows the deck
      // as exported rather than as it would rebuild today.
      cards: session.selectedCards,
      unresolved: session.unresolved,
    );
    refreshHistory();
    await _share.shareApkg(path);
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
            icon: const Icon(Icons.sync),
            tooltip: 'Sync history',
            onPressed: _working ? null : syncNow,
          ),
          IconButton(
            icon: const Icon(Icons.storage_outlined),
            tooltip: 'Dictionary pack',
            onPressed: _openPackScreen,
          ),
        ],
      ),
      body: _working
          ? const Center(child: CircularProgressIndicator())
          : HomeBody(
              packReady: _packReady,
              entries: _entries,
              status: _status,
              onOpen: openEntry,
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _packReady && !_working ? _pickAndBuild : null,
        icon: const Icon(Icons.search),
        label: const Text('Find a song'),
      ),
    );
  }

  /// The production tick, reaching Firebase through the shared project.
  static Future<int?> _defaultSync(ExportHistory history, String deviceId) =>
      syncHistory(history: history, deviceId: deviceId);
}
