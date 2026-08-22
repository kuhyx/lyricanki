import 'package:crdt_sync/crdt_sync.dart';
import 'package:crdt_sync_flutter/crdt_sync_flutter.dart';
import 'package:flutter/material.dart';
import 'package:lyricanki/services/history_sync.dart';
import 'package:sync_settings_ui/sync_settings_ui.dart';

/// The shared sync settings screen, wired to lyricanki's project.
///
/// Every closure it needs is already provided by `crdt_sync_flutter`, so this
/// is the whole of the app-side glue -- the ~390 lines each earlier app wrote
/// by hand now live in that package.
///
/// One tap on both platforms: Android goes through the `google_sign_in`
/// plugin's account picker, and this app's real GTK desktop build -- which
/// the plugin does not support at all -- goes through the OAuth loopback flow
/// in the system browser. Email and password remain as the fallback, and as
/// the machine credential for headless use.
class SyncScreen extends StatelessWidget {
  /// Creates the screen.
  const SyncScreen({super.key});

  /// Opens a signed-in client for the shared project.
  ///
  /// A named method rather than an inline closure so it can be exercised
  /// directly: the shared screen only calls it when the user taps Connect,
  /// which otherwise leaves this line reachable solely through a real
  /// network round trip.
  static Future<FirebaseRestClient?> openClient() => openSync(kSyncApp);

  /// Whether this device already holds a session.
  static Future<bool> probeSession() => isSyncConfigured(kSyncApp);

  /// Signs in through whichever Google flow this platform supports.
  static Future<FirebaseRestClient?> connectWithGoogle() => signInWithGoogle(
    kSyncApp,
    tokenFetcher: () => googleAnyIdToken(
      serverClientId: kServerClientId,
      desktopClientId: kDesktopClientId,
    ),
  );

  /// Whether to offer the Google button at all.
  ///
  /// Double-gated inside the shared package: the platform must ship a flow
  /// *and* the matching client id must be compiled in. A visible control that
  /// can never succeed is worse than no control.
  static bool get googleSupported => googleAnySignInSupported(
    serverClientId: kServerClientId,
    desktopClientId: kDesktopClientId,
  );

  @override
  Widget build(BuildContext context) => SyncSettingsScreen(
    accountLoader: loadAccount,
    accountSaver: saveAccount,
    accountClearer: clearAccount,
    sessionProbe: probeSession,
    firebaseFactory: openClient,
    googleFirebaseFactory: connectWithGoogle,
    googleAvailable: googleSupported,
  );
}
