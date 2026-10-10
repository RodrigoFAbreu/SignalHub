import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/app_controller.dart';

import '../support/harness.dart';
import '../support/phone.dart';
import '../support/screenshot.dart';

void main() {
  setUpAll(loadDesignFonts);

  Finder tab(HomeTab tab) => find.byKey(Key('tab-${tab.name}'));

  for (final (role, tabs) in [
    ('BASIC', [HomeTab.inbox, HomeTab.producers, HomeTab.settings]),
    ('MOD', [HomeTab.inbox, HomeTab.producers, HomeTab.settings]),
    (
      'ADMIN',
      [HomeTab.inbox, HomeTab.producers, HomeTab.people, HomeTab.settings],
    ),
  ]) {
    testWidgets('a $role has the tabs of their role', (tester) async {
      final app = AppHarness(role: role);
      app.backend.publish('e-1', 'Your action: approve the release');
      useDesignPhone(tester);

      await app.start(tester);

      for (final t in HomeTab.values) {
        expect(tab(t), tabs.contains(t) ? findsOneWidget : findsNothing);
      }
      expect(
        find.text('People'),
        tabs.contains(HomeTab.people) ? findsOneWidget : findsNothing,
      );
      await saveScreenshot(tester, find.byKey(screenshotKey), 'shell-$role');
    });
  }

  testWidgets('the unread count is a badge on the Inbox tab', (tester) async {
    final app = AppHarness();
    app.backend
      ..publish('e-1', 'One')
      ..publish('e-2', 'Two')
      ..publish('e-3', 'Three');
    useDesignPhone(tester);
    final semantics = tester.ensureSemantics();

    await app.start(tester);

    expect(
      find.descendant(
        of: find.byKey(const Key('unreadCount')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('Inbox, 3 unread')), findsWidgets);
    semantics.dispose();
  });

  testWidgets('a count above 99 reads 99+, and nothing unread has no badge', (
    tester,
  ) async {
    final app = AppHarness();
    for (var i = 0; i < 101; i++) {
      app.backend.publish('e-$i', 'Event $i');
    }
    useDesignPhone(tester);
    final semantics = tester.ensureSemantics();

    await app.start(tester);

    expect(
      find.descendant(
        of: find.byKey(const Key('unreadCount')),
        matching: find.text('99+'),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('Inbox, 101 unread')), findsWidgets);
    semantics.dispose();
  });

  testWidgets('the inbox has no gear: Settings is a tab', (tester) async {
    final app = AppHarness();
    useDesignPhone(tester);

    await app.start(tester);

    expect(find.byTooltip('Filter events'), findsOneWidget);
    expect(find.byTooltip('Mark all as read'), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    await app.openTab(tester, HomeTab.settings);
    expect(find.widgetWithText(AppBar, 'Settings'), findsOneWidget);
  });

  testWidgets('a tab keeps its place when the bar gains People', (
    tester,
  ) async {
    final app = AppHarness();
    for (var i = 0; i < 40; i++) {
      app.backend.publish('e-$i', 'Event $i');
    }
    useDesignPhone(tester);
    await app.start(tester);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    final scrolled = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    expect(scrolled, greaterThan(0));

    // The host makes this user an admin; the app learns on its next read.
    app.backend
      ..userRole = 'ADMIN'
      ..admin = true;
    await tester.runAsync(app.controller.rereadRegistration);
    await app.settle(tester);

    expect(tab(HomeTab.people), findsOneWidget);
    expect(
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels,
      scrolled,
    );
    expect(
      find.text("Your role changed. You're now an admin."),
      findsOneWidget,
    );
  });

  testWidgets('a demotion says so once and drops People', (tester) async {
    final app = AppHarness(role: 'ADMIN');
    useDesignPhone(tester);
    await app.start(tester);
    await app.openTab(tester, HomeTab.people);

    app.backend
      ..userRole = 'MOD'
      ..admin = false;
    await tester.runAsync(app.controller.rereadRegistration);
    await app.settle(tester);

    expect(tab(HomeTab.people), findsNothing);
    expect(find.text("Your role changed. You're now a Mod."), findsOneWidget);
    // The screen the role lost is not drawn: a plain message, and the bar
    // already has the new role's tabs.
    expect(
      find.text('This screen is not available to your role'),
      findsOneWidget,
    );
    expect(find.text('Ask an admin of this server.'), findsOneWidget);
    // Said once.
    await tester.runAsync(app.controller.rereadRegistration);
    await app.settle(tester);
    expect(app.controller.hasRoleChange, isFalse);
  });

  testWidgets('the bar labels stop growing at 1.3x text', (tester) async {
    final app = AppHarness();
    useDesignPhone(tester, size: const Size(360, 900), textScale: 2);
    await app.start(tester);

    final label = tester.widget<Text>(
      find.descendant(
        of: tab(HomeTab.producers),
        matching: find.text('Producers'),
      ),
    );
    final scale = MediaQuery.of(tester.element(find.text('Producers').last))
        .textScaler
        .scale(12);
    expect(label.data, 'Producers');
    expect(scale, closeTo(15.6, 0.01));
  });
}
