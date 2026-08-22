import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyricanki/services/apkg_share.dart';

/// The share seam over `share_plus`.
///
/// Exercised against a mocked method channel: the real one is an Android
/// platform channel, which throws `MissingPluginException` under
/// `flutter test`. That throw is the whole reason the screen takes an
/// injectable [ApkgShare] rather than calling `SharePlus` directly.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dev.fluttercommunity.plus/share');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return 'dev.fluttercommunity.plus/share/success';
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('passes the deck to the platform share sheet', () async {
    await const ApkgShare().shareApkg('/tmp/decks/Despacito.apkg');

    expect(calls, hasLength(1));
    final arguments = calls.single.arguments as Map<Object?, Object?>;
    expect(arguments['paths'], <String>['/tmp/decks/Despacito.apkg']);
  });

  test('declares the apkg mime type, which is what routes it', () async {
    // AnkiDroid registers ACTION_SEND for application/apkg. Without the type
    // the deck falls through to generic handlers and AnkiDroid is not offered.
    await const ApkgShare().shareApkg('/tmp/decks/Despacito.apkg');

    final arguments = calls.single.arguments as Map<Object?, Object?>;
    expect(arguments['mimeTypes'], <String>['application/apkg']);
  });
}
