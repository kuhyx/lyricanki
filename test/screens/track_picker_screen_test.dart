import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyricanki/models/track.dart';
import 'package:lyricanki/screens/track_picker_screen.dart';
import 'package:lyricanki/services/lrclib_client.dart';

Map<String, dynamic> row(
  int id,
  String name,
  String artist, {
  String lyrics = 'Ay',
  int duration = 273,
}) => <String, dynamic>{
  'id': id,
  'trackName': name,
  'artistName': artist,
  'duration': duration,
  'plainLyrics': lyrics,
};

Future<void> pump(WidgetTester tester, LrclibClient client) =>
    tester.pumpWidget(
      MaterialApp(home: TrackPickerScreen(client: client)),
    );

LrclibClient clientFor(Object body) => LrclibClient(
  httpClient: MockClient(
    (_) async => http.Response.bytes(utf8.encode(jsonEncode(body)), 200),
  ),
);

void main() {
  testWidgets('prompts for a search before anything is typed', (tester) async {
    await pump(tester, clientFor(<Map<String, dynamic>>[]));
    expect(find.text('Search for a song'), findsOneWidget);
  });

  testWidgets('lists every matching recording, not just the first', (
    tester,
  ) async {
    // The whole point of the picker: "Despacito" matches many recordings and
    // one of them is the Bieber remix with English verses.
    await pump(
      tester,
      clientFor(<Map<String, dynamic>>[
        row(36856755, 'Despacito', 'Luis Fonsi'),
        row(36844210, 'Despacito', 'Luis Fonsi & Daddy Yankee ft. Bieber'),
      ]),
    );
    await tester.enterText(find.byType(TextField), 'Despacito');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.text('Despacito'),
      ),
      findsNWidgets(2),
    );
    expect(find.text('#36856755'), findsOneWidget);
    expect(find.text('#36844210'), findsOneWidget);
  });

  testWidgets('shows artist and duration so versions can be told apart', (
    tester,
  ) async {
    await pump(
      tester,
      clientFor(<Map<String, dynamic>>[row(1, 'Despacito', 'Luis Fonsi')]),
    );
    await tester.enterText(find.byType(TextField), 'Despacito');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Luis Fonsi · 4:33'), findsOneWidget);
  });

  testWidgets('returns the tapped track to the caller', (tester) async {
    Track? picked;
    final client = clientFor(<Map<String, dynamic>>[
      row(36856755, 'Despacito', 'Luis Fonsi'),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              picked = await Navigator.of(context).push<Track>(
                MaterialPageRoute<Track>(
                  builder: (_) => TrackPickerScreen(client: client),
                ),
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Despacito');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.text('Despacito'),
      ),
    );
    await tester.pumpAndSettle();
    expect(picked!.id, 36856755);
  });

  testWidgets('hides rows with no lyrics, which cannot become a deck', (
    tester,
  ) async {
    await pump(
      tester,
      clientFor(<Map<String, dynamic>>[
        row(1, 'Instrumental', 'X', lyrics: ''),
      ]),
    );
    await tester.enterText(find.byType(TextField), 'x');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Nothing with lyrics'), findsOneWidget);
  });

  testWidgets('reports a search failure instead of a blank list', (
    tester,
  ) async {
    final client = LrclibClient(
      httpClient: MockClient((_) async => http.Response('', 503)),
    );
    await pump(tester, client);
    await tester.enterText(find.byType(TextField), 'x');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Search failed'), findsOneWidget);
    expect(find.textContaining('503'), findsOneWidget);
  });

  testWidgets('ignores an empty query', (tester) async {
    var calls = 0;
    final client = LrclibClient(
      httpClient: MockClient((_) async {
        calls++;
        return http.Response('[]', 200);
      }),
    );
    await pump(tester, client);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(calls, 0);
  });

  testWidgets('searches from the button as well as the keyboard', (
    tester,
  ) async {
    await pump(
      tester,
      clientFor(<Map<String, dynamic>>[row(1, 'Despacito', 'Luis Fonsi')]),
    );
    await tester.enterText(find.byType(TextField), 'Despacito');
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    expect(find.text('#1'), findsOneWidget);
  });
}
