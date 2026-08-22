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
  ///
  /// [isAndroid] is injectable because the external-storage preference is
  /// Android-only behaviour that must stay tested from a Linux test host.
  PackStore({
    http.Client? httpClient,
    this.directoryOverride,
    bool? isAndroid,
  }) : _http = httpClient ?? http.Client(),
       _isAndroid = isAndroid ?? Platform.isAndroid;

  final http.Client _http;

  final bool _isAndroid;

  /// Base directory to use instead of the real documents directory.
  ///
  /// Only set by tests, so a test run can never write into the live app's
  /// pack directory.
  final Directory? directoryOverride;

  /// Where packs are published. Release assets are free and unmetered for a
  /// public repo, so no server is operated for this.
  ///
  /// **The pack tag is pinned; this must not be `releases/latest`.**
  /// `release-apk.yml` publishes a non-prerelease `vX.Y.Z` on every push to
  /// main, and GitHub resolves `latest` to the newest non-prerelease — so
  /// `latest/download` would point at an APK release holding no `.sqlite`
  /// and every pack download would 404. Bump this tag when a new pack is
  /// published.
  static const String packTag = 'pack-es-v1';

  /// Base directory the pack is downloaded from.
  static const String releaseBase =
      'https://github.com/kuhyx/lyricanki/releases/download/$packTag';

  /// Returns the directory packs live in, creating it when absent.
  ///
  /// **External app storage is preferred on Android.** It resolves to
  /// `/sdcard/Android/data/<package>/files`, which `adb push` can write to and
  /// the app can read with no runtime permission — so a 43 MB pack can be
  /// side-loaded for on-device verification. The documents directory lives
  /// under `/data/data`, which adb cannot write to without root, so using it
  /// would make side-loading impossible.
  ///
  /// Falls back to the documents directory where external storage does not
  /// exist, which covers desktop and iOS.
  ///
  /// The Android check is on the platform rather than on a null
  /// return: `getExternalStorageDirectory()` is not merely absent off
  /// Android, it *throws* `UnimplementedError`, so a `?? fallback` never runs
  /// and the app crashes in `initState` before its first frame.
  Future<Directory> packDirectory() async {
    final base =
        directoryOverride ??
        (_isAndroid ? await getExternalStorageDirectory() : null) ??
        await getApplicationDocumentsDirectory();
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
