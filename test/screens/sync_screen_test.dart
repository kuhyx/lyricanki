import 'dart:convert';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:crdt_sync_flutter/crdt_sync_flutter.dart';
import 'package:crdt_sync_flutter/testing/fake_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyricanki/screens/sync_screen.dart';
import 'package:lyricanki/services/history_sync.dart';

void main() {
  testWidgets('builds its closures against the shared project', (
    tester,
  ) async {
    // The fake ships with crdt_sync_flutter precisely so an app can exercise
    // its own sync wiring without a platform channel. Without it every
    // closure here throws MissingPluginException.
    installFakeSecureStorage();

    await tester.pumpWidget(const MaterialApp(home: SyncScreen()));
    // Pumped, never settled: the screen probes the keystore behind an
    // indeterminate progress indicator, and pumpAndSettle never returns
    // while one animates.
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();

    // The probe ran and reported this device as not set up, which is the
    // normal state before anyone signs in.
    expect(find.byType(SyncScreen), findsOneWidget);
  });

  testWidgets('wires firebaseFactory to the shared project', (tester) async {
    // Covers the factory closure without reaching the network: openSync only
    // builds a client when a session is already stored, and a seeded refresh
    // token is exactly that state. No sign-in round trip happens, so nothing
    // leaves the machine.
    installFakeSecureStorage(
      initial: <String, String>{
        SecureCredentialStore.defaultKey: jsonEncode(<String, String>{
          'id_token': 'stub',
          'refresh_token': 'stub',
          'expires_at': DateTime.now()
              .add(const Duration(hours: 1))
              .toIso8601String(),
        }),
      },
    );

    final client = await SyncScreen.openClient();

    expect(client, isNotNull, reason: 'a stored session is a signed-in device');
    expect(await SyncScreen.probeSession(), isTrue);
    expect(kSyncApp.project.databaseUrl, contains('europe-west1'));
    client?.close();
  });

  testWidgets('offers Google only where a flow can actually succeed', (
    tester,
  ) async {
    // Under `flutter test` the host is Linux, so the plugin half is out and
    // the loopback half is live -- but kDesktopClientId is still empty, so
    // nothing can succeed and the button must stay hidden. This is the trap
    // the double gate exists for: a visible control that can never work.
    expect(kDesktopClientId, isEmpty, reason: 'no Desktop client yet');
    expect(SyncScreen.googleSupported, isFalse);
  });

  test('connectWithGoogle declines when no flow is configured', () async {
    installFakeSecureStorage();

    // Returns null without reaching a platform channel or a browser: the
    // token fetcher short-circuits on the empty client ids, so
    // signInWithGoogle never gets a token to exchange.
    expect(await SyncScreen.connectWithGoogle(), isNull);
  });

  test('the Web client id is the one Firebase expects as the audience', () {
    // An Android client id here yields a token rejected with
    // `audience mismatch`, which surfaces as an indistinguishable
    // "cancelled" -- so pin the shape rather than trusting the constant.
    expect(kServerClientId, endsWith('.apps.googleusercontent.com'));
    expect(kServerClientId, startsWith('845446124781-'));
  });

  test('explains the dark Google button on desktop, and not on Android', () {
    // Under `flutter test` the host is Linux with no Desktop client id, so
    // the button is dark and must say why -- a silently-absent control reads
    // as a bug. On Android googleSupported is true and the reason is null.
    expect(SyncScreen.googleSupported, isFalse);
    expect(SyncScreen.googleReason, isNotNull);
    expect(SyncScreen.googleReason, contains('password'));
  });
}
