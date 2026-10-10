import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/app_controller.dart';
import 'package:signalhub_client/src/ui/widgets/pairing_qr.dart';

import '../support/people_fixture.dart';

void main() {
  for (final (role, summary) in [
    ('ADMIN', '7 devices'),
    ('MOD', '2 devices'),
    ('BASIC', '2 devices'),
  ]) {
    testWidgets('a $role has the Devices row of Settings, with its summary', (
      tester,
    ) async {
      final f = PeopleFixture(role);
      await f.start(tester);

      await f.app.openTab(tester, HomeTab.settings);

      final row = find.byKey(const Key('devices'));
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text(summary)),
        findsOneWidget,
      );

      await tester.tap(row);
      await f.settle(tester);
      expect(find.widgetWithText(AppBar, 'Devices'), findsOneWidget);
    });
  }

  testWidgets('the summary follows a change made on the Devices screen', (
    tester,
  ) async {
    final f = PeopleFixture('MOD');
    await f.start(tester);
    await f.openDevices(tester);

    await tester.tap(find.byTooltip('More actions for Ana - Tablet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revoke'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm')));
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('devices')),
        matching: find.text('1 device'),
      ),
      findsOneWidget,
    );
  });

  group('the pairing QR code', () {
    Future<void> show(WidgetTester tester, Brightness brightness) =>
        tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: const Scaffold(
              body: Center(child: PairingQr('signalhub://pair?x=1')),
            ),
          ),
        );

    testWidgets('is a square of the size asked, named for a screen reader', (
      tester,
    ) async {
      await show(tester, Brightness.dark);

      expect(tester.getSize(find.byType(PairingQr)), const Size.square(200));
      expect(find.bySemanticsLabel('Pairing QR code'), findsOneWidget);
    });

    for (final brightness in Brightness.values) {
      testWidgets('is drawn black on white in the ${brightness.name} theme', (
        tester,
      ) async {
        await show(tester, brightness);

        final painter = tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.byType(PairingQr),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter!;
        final recorder = _RecordingCanvas();
        painter.paint(recorder, const Size.square(200));

        // The plate first, then the dark modules, whatever the theme.
        expect(recorder.colors.first, Colors.white);
        expect(recorder.colors.skip(1).toSet(), {Colors.black});
      });
    }
  });
}

/// A canvas that only records the colours rectangles are drawn in.
class _RecordingCanvas implements Canvas {
  final colors = <Color>[];

  @override
  void drawRect(Rect rect, Paint paint) => colors.add(paint.color);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
