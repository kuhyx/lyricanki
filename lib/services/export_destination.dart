import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Decides where an exported `.apkg` is written.
///
/// **Not the documents directory on Android.** That directory resolves to
/// `/data/user/0/<package>/app_flutter`, which is app-private:
/// no other app can read it, `adb pull` cannot reach it without root, and
/// AnkiDroid's picker cannot see it. An export written there is produced
/// correctly and is then unreachable by the one app it exists to feed.
///
/// External app storage (`/sdcard/Android/data/<package>/files`) is readable
/// by `adb pull` and is where the pack already lives, so exports sit beside
/// the data that produced them. It is *not* browsable by the SAF picker on
/// API 30+, which is why the file is also handed to a share sheet rather than
/// the user being told to go and find it.
///
/// The Android check is on the platform rather than on a null return:
/// `getExternalStorageDirectory()` throws `UnimplementedError` off Android
/// rather than returning null, so a `?? fallback` never runs. This is the
/// same trap [PackStore.packDirectory] documents.
class ExportDestination {
  /// Creates a destination.
  ExportDestination({this.directoryOverride, bool? isAndroid})
    : _isAndroid = isAndroid ?? Platform.isAndroid;

  final bool _isAndroid;

  /// Directory to use instead of the real one.
  ///
  /// Only set by tests, so a test run can never write into the live app's
  /// export directory.
  final Directory? directoryOverride;

  /// Returns the directory exports live in, creating it when absent.
  Future<Directory> exportDirectory() async {
    final base =
        directoryOverride ??
        (_isAndroid ? await getExternalStorageDirectory() : null) ??
        await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'exports'));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Returns the path an export named after [trackName] would occupy.
  ///
  /// The name is reduced to ASCII word characters: track titles carry
  /// slashes, colons and quotes that are either illegal in a filename or
  /// silently reinterpreted as path separators.
  Future<String> pathFor(String trackName) async {
    final safe = trackName.replaceAll(RegExp('[^A-Za-z0-9]+'), '_');
    return p.join((await exportDirectory()).path, '$safe.apkg');
  }
}
