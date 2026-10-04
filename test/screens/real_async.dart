import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real-time waits for widget tests whose work runs outside fake async.
///
/// A fixed `Future.delayed` flakes when the CPU is starved (a capped CI box, a
/// parallel build), so these wait for the screen to say the work is done.

/// Pumps real time in small steps until [done] holds, for at most [timeout].
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final end = DateTime.now().add(timeout);
  await tester.pump();
  while (!done() && DateTime.now().isBefore(end)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

/// Whether a progress indicator is on screen, i.e. async work is still running.
bool isBusy() =>
    find.byType(CircularProgressIndicator).evaluate().isNotEmpty ||
    find.byType(LinearProgressIndicator).evaluate().isNotEmpty;

/// Whether [text] is on screen.
bool hasText(String text) => find.text(text).evaluate().isNotEmpty;
