import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/models/event.dart';
import 'package:signalhub_client/src/ui/event_style.dart';
import 'package:signalhub_client/src/ui/inbox_screen.dart';

void main() {
  final createdAt = DateTime.utc(2026, 9, 25, 18, 42);

  Event event(EventSeverity severity) => Event(
    id: 'e-1',
    producer: const EventProducer(
      id: 'p-1',
      name: 'a-producer-with-a-rather-long-name',
    ),
    category: EventCategory.parse('BLOCKED'),
    severity: severity,
    title: 'Nightly build failed',
    createdAt: createdAt,
  );

  for (final severity in EventSeverity.values) {
    testWidgets('a ${severity.label} row shows its time in full', (
      tester,
    ) async {
      // A phone's width at the default text size.
      tester.view
        ..physicalSize = const Size(360, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: EventTile(event(severity)))),
      );

      final time = find.byKey(const Key('eventTime'));
      expect(tester.widget<Text>(time).data, formatTimestamp(createdAt));
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: time, matching: find.byType(RichText)),
      );
      expect(paragraph.didExceedMaxLines, isFalse);
      final full = TextPainter(
        text: paragraph.text,
        textDirection: TextDirection.ltr,
        textScaler: paragraph.textScaler,
      )..layout();
      expect(paragraph.size.width, greaterThanOrEqualTo(full.width));
      full.dispose();
    });
  }
}
