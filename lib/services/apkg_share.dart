import 'dart:io';

import 'package:share_plus/share_plus.dart';

/// Hands an exported `.apkg` to whatever app can import it.
///
/// A thin seam over `share_plus` so widget tests can observe the call without
/// a platform channel: `SharePlus` reaches the Android share sheet through
/// one, which is unavailable under `flutter test` and throws
/// `MissingPluginException` rather than returning null.
///
/// The share sheet exists because the file's *location* cannot be
/// communicated usefully on Android. Exports land in external app storage,
/// which the SAF picker refuses to browse from API 30 on, so telling the user
/// a path gives them somewhere they cannot navigate to. AnkiDroid registers
/// `ACTION_SEND` for `application/apkg`, making the sheet the supported
/// handoff between the two apps.
class ApkgShare {
  /// Creates a sharer.
  ///
  /// [isAndroid] is only overridden by tests.
  ApkgShare({bool? isAndroid}) : _isAndroid = isAndroid ?? Platform.isAndroid;

  final bool _isAndroid;

  /// Offers the deck at [path] to other apps.
  ///
  /// **Android only, deliberately.** share_plus's Linux backend is a mailto:
  /// url_launcher shim that throws `UnimplementedError('Sharing files not
  /// supported on Linux')` for any share carrying files, so calling it
  /// unconditionally would replace a working desktop export with a crash.
  /// Desktop does not need it: the export lands in the documents directory,
  /// which the user can open in a file manager and Anki can import.
  Future<void> shareApkg(String path) async {
    if (!_isAndroid) return;
    await SharePlus.instance.share(
      ShareParams(
        // The mime type is what routes the file: AnkiDroid registers
        // ACTION_SEND for application/apkg, so declaring it puts AnkiDroid in
        // the sheet instead of burying the deck under generic file handlers.
        files: <XFile>[XFile(path, mimeType: 'application/apkg')],
      ),
    );
  }
}
