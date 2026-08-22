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
/// No Google button: `google_sign_in` is an Android/iOS/web plugin and this
/// app also runs on Linux desktop, so sign-in here is email and password,
/// which works everywhere.
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

  @override
  Widget build(BuildContext context) => const SyncSettingsScreen(
    accountLoader: loadAccount,
    accountSaver: saveAccount,
    accountClearer: clearAccount,
    sessionProbe: probeSession,
    firebaseFactory: openClient,
  );
}
