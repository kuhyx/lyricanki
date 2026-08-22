import 'package:crdt_sync/crdt_sync.dart';
import 'package:crdt_sync_flutter/crdt_sync_flutter.dart';
import 'package:lyricanki/services/export_history.dart';

/// The shared `kuhy-syncs` project, so the history appears on every device.
///
/// Safe to commit, and deliberately committed: the Web API key is a public
/// identifier that already ships inside every APK, and the security rules --
/// not its secrecy -- are what protect the data. The account's email and
/// password are never here; they are entered once per device and kept in the
/// OS keystore.
///
/// `databaseUrl` must be the **regional** host. The plain `*.firebaseio.com`
/// form answers 404 with a `correctUrl` body rather than an obvious error,
/// which reads like an auth failure and wastes a debugging session.
const SyncApp kSyncApp = SyncApp(
  project: FirebaseProject(
    apiKey: 'AIzaSyCF_sA3xCMehAYXK8eND-rAygb9NXXW_8E',
    databaseUrl:
        'https://kuhy-syncs-default-rtdb.europe-west1.firebasedatabase.app',
  ),
  // Load-bearing: `signInWithIdp` signs in *or signs up*, so an unlinked
  // account authenticates fine and is then denied every read and write -- a
  // sync that silently never syncs. This catches it at sign-in.
  expectedUid: 'OvA2REQyLIhAHOEjzwS1o877rgG3',
);

/// The project's **Web** OAuth client id: the audience for the ID tokens the
/// Android one-tap flow mints.
///
/// Public by design, exactly like [kSyncApp]'s `apiKey` -- it ships inside
/// every APK, and the security rules, not its secrecy, protect the data.
///
/// A plain const rather than a `--dart-define`, deliberately: as a
/// compile-time environment value it was empty in every build that mattered,
/// because phone-deploy and CI both run a bare `flutter build apk --release`.
/// That produced a visible Google button that always reported "cancelled".
///
/// An *Android* client id here yields a token Firebase rejects with
/// `audience mismatch`; it must be the Web one.
const String kServerClientId =
    '845446124781-prdoherj0v64vc6egvvcp3l0693khaur.apps.googleusercontent.com';

/// A **Desktop**-type OAuth client, for the loopback flow this app's real GTK
/// build uses -- `google_sign_in` has no Linux implementation.
///
/// Empty until the Desktop client is registered in the console. While it is
/// empty `googleAnySignInSupported` reports false on desktop, so the button
/// stays hidden there rather than appearing and failing.
const String kDesktopClientId = '';

/// Where this app's logs live in the shared database.
const String kSyncPathPrefix = 'lyricanki-sync/devices';

/// Builds a signed-in client, or null when this device is not set up.
typedef FirebaseFactory = Future<FirebaseRestClient?> Function();

/// Merges the export history with every other device's.
///
/// Manual, never automatic: the list is rendered from the local log, which is
/// always authoritative and instant, so a network tick is never on the path
/// that paints the home screen. That is the whole reason the reported bug --
/// an empty screen after a finished export -- cannot come back as a timeout.
///
/// Returns how many entries the history holds afterwards, or null when this
/// device has no Firebase session. Not being set up is a normal state, not an
/// error: the app keeps working, it just does not share.
Future<int?> syncHistory({
  required ExportHistory history,
  required String deviceId,
  FirebaseFactory? firebaseFactory,
}) async {
  final client = await (firebaseFactory ?? () => openSync(kSyncApp))();
  if (client == null) return null;
  try {
    final merged = await syncLog(
      client: client,
      deviceId: deviceId,
      pathPrefix: kSyncPathPrefix,
      localLog: history.snapshot(),
      encode: logToJson,
      decode: logFromJson,
      filename: ExportHistory.fileName,
      commitMessage: 'lyricanki: export history',
    );
    await history.replaceAll(merged);
    return history.all().length;
  } finally {
    client.close();
  }
}
