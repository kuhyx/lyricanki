import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:lyricanki/models/track.dart';
import 'package:lyricanki/services/lrclib_client.dart';

/// Searches LRCLIB and lets the user pick exactly which recording to use.
///
/// **Picking matters.** A bare "Despacito" search returns about 20 rows, and
/// one of them is the Justin Bieber remix, whose English verses would poison a
/// Spanish deck. So every row shows artist, duration and its LRCLIB id rather
/// than the app guessing which is canonical.
class TrackPickerScreen extends StatefulWidget {
  /// Creates the picker.
  const TrackPickerScreen({required this.client, super.key});

  /// LRCLIB client to search with.
  final LrclibClient client;

  @override
  State<TrackPickerScreen> createState() => _TrackPickerScreenState();
}

class _TrackPickerScreenState extends State<TrackPickerScreen> {
  final TextEditingController _query = TextEditingController();
  List<Track> _results = <Track>[];
  bool _searching = false;
  String? _error;
  bool _searched = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final text = _query.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await widget.client.search(text);
      if (!mounted) return;
      setState(() {
        // Only tracks with lyrics can become a deck.
        _results = results.where((t) => t.hasLyrics).toList();
        _searched = true;
      });
    } on LrclibException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Find a song')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: TextField(
              controller: _query,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                labelText: 'Song or artist',
                hintText: 'Despacito',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _searching ? null : _search,
                ),
              ),
            ),
          ),
          if (_searching) const LinearProgressIndicator(),
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_error != null) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Search failed',
        message: _error!,
      );
    }
    if (_results.isEmpty) {
      return EmptyState(
        icon: Icons.library_music_outlined,
        title: _searched ? 'Nothing with lyrics' : 'Search for a song',
        message: _searched
            ? 'LRCLIB has no lyrics for that search. Try the artist too.'
            : 'Several recordings usually share a title, so pick the exact '
                  'one you want — versions differ, sometimes in language.',
      );
    }
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final track = _results[index];
        return ListTile(
          title: Text(track.name),
          subtitle: Text('${track.artist} · ${track.durationLabel}'),
          // The id is shown because it is what pins a recording: the
          // acceptance test names 36856755 specifically.
          trailing: Text(
            '#${track.id}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          onTap: () => Navigator.of(context).pop(track),
        );
      },
    );
  }
}
