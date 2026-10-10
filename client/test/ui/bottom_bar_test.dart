import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/app_controller.dart';

import '../support/harness.dart';
import '../support/phone.dart';
import '../support/producers_backend.dart';
import '../support/screenshot.dart';

void main() {
  setUpAll(loadDesignFonts);

  Finder tab(HomeTab tab) => find.byKey(Key('tab-${tab.name}'));

  Future<AppHarness> open(
    WidgetTester tester, {
    String role = 'BASIC',
    int unread = 0,
    Size size = const Size(412, 892),
    double textScale = 1,
    Brightness brightness = Brightness.dark,
  }) async {
    final app = AppHarness(role: role);
    FakeProducers(app.backend);
    for (var i = 0; i < unread; i++) {
      app.backend.publish('e$i', 'Event $i');
    }
    useDesignPhone(
      tester,
      size: size,
      textScale: textScale,
      brightness: brightness,
    );
    await app.start(tester);
    return app;
  }

  Finder badge() => find.byKey(const Key('unreadCount'));

  Size badgeSize(WidgetTester tester) => tester.getSize(
    find
        .ancestor(
          of: find.descendant(of: badge(), matching: find.byType(Text)),
          matching: find.byType(DecoratedBox),
        )
        .first,
  );

  testWidgets('the bar is 80 dp high above the system inset', (tester) async {
    await open(tester);

    expect(tester.getSize(find.byType(NavigationBar)).height, 80);
  });

  group('the unread badge', () {
    testWidgets('is a 16 dp pill with the number', (tester) async {
      await open(tester, unread: 3);

      expect(badgeSize(tester).height, 16);
      expect(
        find.descendant(of: badge(), matching: find.text('3')),
        findsOneWidget,
      );
    });

    testWidgets('99 and 99+ stay inside the 64 dp indicator', (tester) async {
      await open(tester, unread: 101);

      expect(
        find.descendant(of: badge(), matching: find.text('99+')),
        findsOneWidget,
      );
      expect(badgeSize(tester).height, 16);
      expect(badgeSize(tester).width, lessThan(64 - 24));
    });

    testWidgets('is absent with nothing unread', (tester) async {
      await open(tester);

      expect(badge(), findsNothing);
    });

    testWidgets('says the real count to a screen reader', (tester) async {
      final semantics = tester.ensureSemantics();
      await open(tester, unread: 101);

      expect(find.bySemanticsLabel(RegExp('Inbox, 101 unread')), findsWidgets);
      semantics.dispose();
    });

    testWidgets('sits on the Inbox tab only', (tester) async {
      await open(tester, unread: 3);

      expect(
        find.descendant(of: tab(HomeTab.inbox), matching: badge()),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tab(HomeTab.producers), matching: badge()),
        findsNothing,
      );
    });
  });

  group('switching tabs', () {
    testWidgets('is not animated', (tester) async {
      final app = await open(tester, unread: 1);
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.animationDuration, Duration.zero);

      await tester.tap(tab(HomeTab.settings));
      await tester.pump();

      // One frame later the new tab is there and nothing is moving.
      expect(find.widgetWithText(AppBar, 'Settings'), findsOneWidget);
      expect(app.controller.tab, HomeTab.settings);
    });

    testWidgets('keeps the filled glyph on the selected tab', (tester) async {
      final app = await open(tester);

      Finder glyph(HomeTab t, IconData icon) =>
          find.descendant(of: tab(t), matching: find.byIcon(icon));
      expect(glyph(HomeTab.inbox, Icons.inbox), findsOneWidget);
      expect(glyph(HomeTab.producers, Icons.sensors_outlined), findsOneWidget);

      await app.openTab(tester, HomeTab.producers);

      expect(glyph(HomeTab.producers, Icons.sensors), findsOneWidget);
      expect(glyph(HomeTab.inbox, Icons.inbox_outlined), findsOneWidget);
    });
  });

  for (final (role, tabs) in [('BASIC', 3), ('MOD', 3), ('ADMIN', 4)]) {
    testWidgets('the labels of a $role never wrap at 360 dp and 200 % text', (
      tester,
    ) async {
      await open(
        tester,
        role: role,
        unread: 150,
        size: const Size(360, 800),
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationDestination), findsNWidgets(tabs));
      final labels = [
        'Inbox',
        'Producers',
        if (tabs == 4) 'People',
        'Settings',
      ];
      for (final label in labels) {
        final box = tester.getSize(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          ),
        );
        // One line of the capped 1.3x label: 12 * 1.3 * 1.33 line height.
        expect(box.height, lessThanOrEqualTo(22), reason: label);
      }
      // The bar grows only by the extra line height.
      expect(tester.getSize(find.byType(NavigationBar)).height, lessThan(96));
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('draws the bar without overflow, $brightness', (tester) async {
      await open(tester, unread: 5, brightness: brightness);

      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationBar), findsOneWidget);
    });
  }
}
