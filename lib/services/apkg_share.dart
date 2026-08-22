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
  const ApkgShare();

  /// Offers the deck at [path] to other apps.
  Future<void> shareApkg(String path) async {
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
