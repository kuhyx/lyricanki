import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Progress of a pack download, from 0 to 1, or `null` while the total size
/// is still unknown.
typedef DownloadProgress = void Function(double? fraction);

/// Locates, downloads and lists dictionary packs on the device.
///
/// A pack is a large file (the Spanish one is ~43 MB), so it is never bundled
/// in the APK — Q12 has the app ship with no dictionaries at all. It lives in
/// the app's documents directory, and can arrive either by download or by
/// being pushed there directly, which is what on-device verification uses.
class PackStore {
  /// Creates a store, optionally over an injected [httpClient] and a fixed
  /// [directoryOverride] so tests never touch the real documents directory.
  PackStore({http.Client? httpClient, this.directoryOverride})
    : _http = httpClient ?? http.Client();

  final http.Client _http;

  /// Base directory to use instead of the real documents directory.
  ///
  /// Only set by tests, so a test run can never write into the live app's
  /// pack directory.
  final Directory? directoryOverride;

  /// Where packs are published. Release assets are free and unmetered for a
  /// public repo, so no server is operated for this.
  static const String releaseBase =
      'https://github.com/kuhyx/lyricanki/releases/latest/download';

  /// Returns the directory packs live in, creating it when absent.
  Future<Directory> packDirectory() async {
    final base = directoryOverride ?? await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'packs'));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Returns the file a pack for [language] would occupy, downloaded or not.
  Future<File> packFile(String language) async =>
      File(p.join((await packDirectory()).path, 'lyricanki-$language.sqlite'));

  /// Whether a pack for [language] is already on the device.
  ///
  /// An empty file counts as absent: an interrupted download leaves one
  /// behind, and treating it as present would fail later with a confusing
  /// SQLite error instead of simply downloading again.
  Future<bool> hasPack(String language) async {
    final file = await packFile(language);
    return file.existsSync() && file.lengthSync() > 0;
  }

  /// Returns the language codes of every pack present.
  Future<List<String>> installedLanguages() async {
    final dir = await packDirectory();
    final codes = <String>[];
    for (final entity in dir.listSync()) {
      if (entity is! File || entity.lengthSync() == 0) continue;
      final name = p.basename(entity.path);
      final match = RegExp(r'^lyricanki-(\w+)\.sqlite$').firstMatch(name);
      if (match != null) codes.add(match.group(1)!);
    }
    return codes..sort();
  }

  /// Downloads the pack for [language], reporting progress to [onProgress].
  ///
  /// Streams to a temporary file and renames on completion, so an interrupted
  /// download can never be mistaken for a usable pack.
  Future<File> download(
    String language, {
    DownloadProgress? onProgress,
    Uri? sourceOverride,
  }) async {
    final target = await packFile(language);
    final temp = File('${target.path}.part');
    final uri =
        sourceOverride ?? Uri.parse('$releaseBase/lyricanki-$language.sqlite');

    final request = http.Request('GET', uri);
    final response = await _http.send(request);
    if (response.statusCode != 200) {
      throw PackDownloadException(
        'Download failed with HTTP ${response.statusCode}.',
      );
    }

    final total = response.contentLength;
    var received = 0;
    final sink = temp.openWrite();
    try {
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(total == null ? null : received / total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (temp.lengthSync() == 0) {
      await temp.delete();
      throw const PackDownloadException('Download produced an empty file.');
    }
    if (target.existsSync()) {
      await target.delete();
    }
    return temp.rename(target.path);
  }

  /// Deletes the pack for [language], if present.
  Future<void> delete(String language) async {
    final file = await packFile(language);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  /// Releases the underlying HTTP client.
  void close() => _http.close();
}

/// Thrown when a pack cannot be downloaded.
class PackDownloadException implements Exception {
  /// Creates the exception.
  const PackDownloadException(this.message);

  /// Human-readable cause, shown in the UI.
  final String message;

  @override
  String toString() => 'PackDownloadException: $message';
}
