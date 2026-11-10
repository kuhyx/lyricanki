import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two or more letters in a row: a word. Numbers, dates and symbols pass.
final RegExp _word = RegExp(r'\p{L}{2,}', unicode: true);

/// Every string painted by a [Text] or [RichText] currently on screen.
///
/// RichText covers what Text builds internally plus anything built by hand;
/// Text is read too so a test failure names the widget's own data.
List<String> paintedStrings(WidgetTester tester) => <String>[
  for (final widget in tester.widgetList<RichText>(find.byType(RichText)))
    widget.text.toPlainText(),
];

/// Fails if anything on screen paints a word that is not [content].
///
/// [content] lists strings a human wrote or the user's data supplies (track
/// names, lemmas, glosses, lyric lines, unit symbols next to a number). Each
/// is cut out of a painted string before the word check, so chrome hiding
/// next to content is still caught. kuhy's textgate rule: nothing he sees has
/// words unless he asked for them.
void expectNoWords(WidgetTester tester, {Set<String> content = const {}}) {
  // Longest first, so "Luis Fonsi" is cut before a shorter "Luis" could split it.
  final cuts = content.toList()..sort((a, b) => b.length - a.length);
  final offenders = <String>[];
  for (final painted in paintedStrings(tester)) {
    var rest = painted;
    for (final cut in cuts) {
      rest = rest.replaceAll(cut, ' ');
    }
    if (_word.hasMatch(rest)) offenders.add(painted);
  }
  expect(offenders, isEmpty, reason: 'chrome words painted on screen');
}
