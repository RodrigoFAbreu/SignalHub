import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/app_controller.dart';
import 'package:signalhub_client/src/onboarding/onboarding_store.dart';
import 'package:signalhub_client/src/push/push_service.dart';
import 'package:signalhub_client/src/ui/devices_screen.dart';
import 'package:signalhub_client/src/ui/role_lacks_screen.dart';
import 'package:signalhub_client/src/ui/widgets/skeleton.dart';

import '../support/first_run_support.dart';
import '../support/phone.dart';
import '../support/screenshot.dart';

void main() {
  setUpAll(loadDesignFonts);

  Finder byKey(String key) => find.byKey(Key(key));

  Future<void> shot(WidgetTester tester, String name) =>
      saveScreenshot(tester, byKey('screenshot'), name);

  FirstRunHarness harness({String role = 'BASIC'}) =>
      FirstRunHarness(role: role, step: OnboardingStep.done);

  testWidgets('5a: the inbox in the light theme', (tester) async {
    final app = harness();
    app.backend
      ..publish(
        'e-5',
        'Weekly report is ready',
        category: 'INFO',
        severity: 'NORMAL',
        readAt: '2026-09-24T12:10:00Z',
        producer: {'id': 'p-4', 'name': 'ana-reports'},
      )
      ..publish(
        'e-4',
        'Deploy to staging done',
        category: 'COMPLETED',
        severity: 'LOW',
        readAt: '2026-09-25T12:10:00Z',
        producer: {'id': 'p-3', 'name': 'ci-pipeline'},
      )
      ..publish(
        'e-3',
        'Disk almost full on nas-01',
        category: 'BLOCKED',
        severity: 'CRITICAL',
        producer: {'id': 'p-2', 'name': 'homelab-monitor'},
      )
      ..publish(
        'e-2',
        'Nightly backup finished',
        category: 'INFO',
        severity: 'NORMAL',
        producer: {'id': 'p-5', 'name': 'backup-jobs'},
      )
      ..publish(
        'e-1',
        'Your action: approve the release',
        category: 'ACTION_REQUIRED',
        severity: 'HIGH',
        producer: {'id': 'p-3', 'name': 'ci-pipeline'},
      );
    useDesignPhone(tester, brightness: Brightness.light);

    await app.start(tester);

    expect(find.text('Your action: approve the release'), findsOneWidget);
    expect(find.text('Action required · High · ci-pipeline'), findsOneWidget);
    expect(find.text('Blocked · Critical · homelab-monitor'), findsOneWidget);
    expect(find.text('Completed · Low · ci-pipeline'), findsOneWidget);
    // Three unread: the badge says so, in the error colour.
    final badge = tester.widget<Badge>(byKey('unreadCount'));
    expect(badge.label, isA<Text>());
    expect(
      find.descendant(of: byKey('unreadCount'), matching: find.text('3')),
      findsOneWidget,
    );
    expect(byKey('unread'), findsNWidgets(3));
    expect(
      Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
      Brightness.light,
    );
    await shot(tester, '5a');
  });

  group('an empty inbox', () {
    testWidgets('4c: with nothing subscribed points to Producers', (
      tester,
    ) async {
      final app = harness();
      FakeVisibleProducers().install(app.backend);
      useDesignPhone(tester);

      await app.start(tester);

      expect(find.text('No events yet'), findsOneWidget);
      expect(
        find.text('Events show up here once you subscribe to a producer.'),
        findsOneWidget,
      );
      // No badge on the tab while there is nothing unread.
      expect(byKey('unreadCount'), findsNothing);
      await shot(tester, '4c');

      await tester.tap(find.text('Find producers'));
      await app.settle(tester);
      expect(app.controller.tab, HomeTab.producers);
    });

    testWidgets('with subscriptions but no events says nothing new', (
      tester,
    ) async {
      final app = harness();
      FakeVisibleProducers()
        ..add('p-1', 'ci-pipeline')
        ..install(app.backend);
      useDesignPhone(tester);

      await app.start(tester);

      expect(find.text('Nothing new from your producers'), findsOneWidget);
      expect(find.text('Find producers'), findsNothing);
      expect(byKey('unreadCount'), findsNothing);
    });

    testWidgets('does not say nothing is subscribed when that is not known', (
      tester,
    ) async {
      final app = harness();
      FakeVisibleProducers()
        ..fails = true
        ..install(app.backend);
      useDesignPhone(tester);

      await app.start(tester);

      expect(find.text('Nothing new from your producers'), findsOneWidget);
    });

    testWidgets('after a filter says which filters match nothing', (
      tester,
    ) async {
      final app = harness();
      app.backend.publish('e-1', 'Build failed');
      FakeVisibleProducers()
        ..add('p-1', 'nightly-build')
        ..install(app.backend);
      useDesignPhone(tester);
      await app.start(tester);

      await tester.runAsync(
        () => app.controller.setFilter(
          app.controller.filter.copyWith(unreadOnly: true),
        ),
      );
      app.backend.events.first['readAt'] = '2026-09-25T12:10:00Z';
      await tester.runAsync(app.controller.refresh);
      await app.settle(tester);

      expect(find.text('No events match these filters'), findsOneWidget);
      await tester.tap(find.text('Clear filters'));
      await app.settle(tester);
      expect(find.text('Build failed'), findsOneWidget);
    });

    testWidgets('has no Mark all as read while there is nothing to mark', (
      tester,
    ) async {
      final app = harness();
      useDesignPhone(tester);

      await app.start(tester);

      expect(find.byTooltip('Filter events'), findsOneWidget);
      expect(find.byTooltip('Mark all as read'), findsNothing);
    });
  });

  group('a list that does not load', () {
    testWidgets('4l: shows skeleton rows, not a spinner, while it loads', (
      tester,
    ) async {
      final app = harness();
      app.backend.publish('e-1', 'Build failed');
      final gate = FakeInboxGate()..hold = Completer<void>();
      gate.install(app.backend);
      useDesignPhone(tester);
      await app.start(tester, wait: false);

      expect(find.byType(SkeletonRows), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await shot(tester, '4l');

      gate.hold!.complete();
      await app.settle(tester);
      expect(find.text('Build failed'), findsOneWidget);
      expect(find.byType(SkeletonRows), findsNothing);
    });

    testWidgets('4i: with no list is an empty state with Try again', (
      tester,
    ) async {
      final app = harness();
      app.backend.offline = true;
      useDesignPhone(tester);

      await app.start(tester);

      expect(find.text("Couldn't load events"), findsOneWidget);
      expect(find.text('Check your connection and try again.'), findsOneWidget);
      await shot(tester, '4i');

      app.backend
        ..offline = false
        ..publish('e-1', 'Build failed');
      await tester.tap(find.text('Try again'));
      await app.settle(tester);
      expect(find.text('Build failed'), findsOneWidget);
      expect(find.text("Couldn't load events"), findsNothing);
    });

    testWidgets('a server error says SignalHub had a problem', (tester) async {
      final app = harness();
      final gate = FakeInboxGate()..status = 500;
      gate.install(app.backend);
      useDesignPhone(tester);

      await app.start(tester);

      expect(find.text("Couldn't load events"), findsOneWidget);
      expect(
        find.text('SignalHub had a problem. Try again in a moment.'),
        findsOneWidget,
      );
    });
  });

  group('an older list', () {
    testWidgets('4j: offline keeps the list under a neutral banner with its '
        'time, and pauses the changes', (tester) async {
      final app = harness();
      app.backend.publish('e-1', 'Build failed');
      useDesignPhone(tester);
      await app.start(tester);
      final loaded = app.controller.inboxLoadedAt!;
      String two(int n) => n.toString().padLeft(2, '0');
      final time = '${two(loaded.hour)}:${two(loaded.minute)}';

      app.backend.offline = true;
      await tester.runAsync(app.controller.refresh);
      await app.settle(tester);

      expect(find.text('Build failed'), findsOneWidget);
      expect(
        find.text(
          "You're offline. This is the list from $time. Changes are paused "
          "until you're back.",
        ),
        findsOneWidget,
      );
      final markAll = tester.widget<IconButton>(byKey('markAllRead'));
      expect(markAll.onPressed, isNull);
      await shot(tester, '4j');

      // It clears itself when the connection returns and the list refreshes.
      app.backend.offline = false;
      await tester.runAsync(app.controller.refresh);
      await app.settle(tester);
      expect(find.textContaining("You're offline"), findsNothing);
      expect(
        tester.widget<IconButton>(byKey('markAllRead')).onPressed,
        isNotNull,
      );
    });

    testWidgets('a refresh that failed keeps the list, with Try again', (
      tester,
    ) async {
      final app = harness();
      app.backend.publish('e-1', 'Build failed');
      final gate = FakeInboxGate();
      gate.install(app.backend);
      useDesignPhone(tester);
      await app.start(tester);

      gate.status = 500;
      await tester.runAsync(app.controller.refresh);
      await app.settle(tester);

      expect(find.text('Build failed'), findsOneWidget);
      expect(
        find.textContaining("Couldn't refresh. This is the list from"),
        findsOneWidget,
      );
      gate.status = null;
      await tester.tap(find.text('Try again'));
      await app.settle(tester);
      expect(find.textContaining("Couldn't refresh"), findsNothing);
    });
  });

  group('a screen or an action the role does not have', () {
    testWidgets('4m: names the screen, who it is for and who can help', (
      tester,
    ) async {
      final app = harness(role: 'ADMIN');
      useDesignPhone(tester);
      await app.start(tester);
      await tester.tap(byKey('tab-people'));
      await app.settle(tester);

      app.backend
        ..userRole = 'MOD'
        ..admin = false;
      await tester.runAsync(app.controller.rereadRegistration);
      await app.settle(tester);

      expect(find.widgetWithText(AppBar, 'People'), findsOneWidget);
      expect(find.text("You can't open this"), findsOneWidget);
      expect(
        find.text(
          'People is for admins of this server. If you need it, ask an admin.',
        ),
        findsOneWidget,
      );
      expect(byKey('tab-people'), findsNothing);
      await shot(tester, '4m');

      await tester.tap(find.text('Back to Inbox'));
      await app.settle(tester);
      expect(app.controller.tab, HomeTab.inbox);
      expect(find.text("You can't open this"), findsNothing);
    });

    testWidgets('its back arrow goes to the Inbox, and is named Back', (
      tester,
    ) async {
      final app = harness(role: 'ADMIN');
      useDesignPhone(tester);
      await app.start(tester);
      await tester.tap(byKey('tab-people'));
      await app.settle(tester);
      app.backend
        ..userRole = 'BASIC'
        ..admin = false;
      await tester.runAsync(app.controller.rereadRegistration);
      await app.settle(tester);

      await tester.tap(find.byTooltip('Back'));
      await app.settle(tester);

      expect(app.controller.tab, HomeTab.inbox);
    });

    testWidgets('pushed over a screen, it pops back to it', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const RoleLacksScreen(
                      screen: 'Connect a device',
                      body:
                          'Connecting a device is for Mods and admins. Ask an '
                          'admin of this server.',
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Connect a device'), findsOneWidget);
      await tester.tap(find.text('Back to Inbox'));
      await tester.pumpAndSettle();

      expect(find.text('open'), findsOneWidget);
    });

    test('4m2: the message for a refused action is the one decided', () {
      expect(
        roleRefusedMessage,
        "Your role doesn't allow this. It may have changed.",
      );
    });

    testWidgets('fits 360 dp at 200 % text', (tester) async {
      useDesignPhone(tester, size: const Size(360, 640), textScale: 2);
      await tester.pumpWidget(const MaterialApp(home: RoleLacksScreen()));

      expect(tester.takeException(), isNull);
      expect(find.text('Back to Inbox'), findsOneWidget);
    });
  });

  group('an event that is not in the inbox any more', () {
    testWidgets('4o: a tapped push for it says so, in no error colour', (
      tester,
    ) async {
      final app = harness();
      app.backend.publish('e-1', 'Build failed');
      useDesignPhone(tester);
      await app.start(tester);

      app.push.received.add(
        const PushNotice(title: 'Gone', eventId: 'e-404', opened: true),
      );
      await app.settle(tester);

      expect(find.widgetWithText(AppBar, 'Event'), findsOneWidget);
      expect(
        find.text("This event isn't in your inbox any more"),
        findsOneWidget,
      );
      expect(
        find.text(
          'You may have unsubscribed from its producer, or it was deleted. If '
          'you subscribe again, its older events come back.',
        ),
        findsOneWidget,
      );
      // One button, and no retry.
      expect(find.byType(FilledButton), findsOneWidget);
      expect(byKey('retryEvent'), findsNothing);
      expect(find.byIcon(Icons.event_busy), findsOneWidget);
      await shot(tester, '4o');

      await tester.tap(find.text('Back to Inbox'));
      await app.settle(tester);
      expect(find.widgetWithText(AppBar, 'SignalHub'), findsOneWidget);
    });

    testWidgets('an event deleted while its row is open is taken out of the '
        'inbox', (tester) async {
      final app = harness();
      app.backend
        ..publish('e-2', 'Disk full')
        ..publish('e-1', 'Build failed');
      useDesignPhone(tester);
      await app.start(tester);
      expect(find.text('2'), findsOneWidget);

      // The operator deletes it, then the owner taps its row.
      app.backend.events.removeWhere((e) => e['id'] == 'e-1');
      await tester.tap(find.text('Build failed'));
      await app.settle(tester);

      expect(
        find.text("This event isn't in your inbox any more"),
        findsOneWidget,
      );
      // No actions on an event that is not there.
      expect(find.byTooltip('Mark as read'), findsNothing);
      expect(byKey('markRead'), findsNothing);
      await tester.tap(find.text('Back to Inbox'));
      await app.settle(tester);
      expect(find.text('Build failed'), findsNothing);
      expect(find.text('Disk full'), findsOneWidget);
      // The count follows.
      expect(app.controller.unreadCount, 1);
      expect(app.controller.events.map((e) => e.id), ['e-2']);
    });

    testWidgets('marking an event read that is gone says so too', (
      tester,
    ) async {
      final app = harness();
      app.backend.publish(
        'e-1',
        'Build failed',
        readAt: '2026-09-25T12:10:00Z',
      );
      useDesignPhone(tester);
      await app.start(tester);
      await tester.tap(find.text('Build failed'));
      await app.settle(tester);
      expect(find.text('Mark as unread'), findsOneWidget);

      app.backend.events.clear();
      await tester.tap(find.text('Mark as unread'));
      await app.settle(tester);

      expect(
        find.text("This event isn't in your inbox any more"),
        findsOneWidget,
      );
      expect(app.controller.events, isEmpty);
    });

    testWidgets('fits 360 dp at 200 % text', (tester) async {
      final app = harness();
      useDesignPhone(tester, size: const Size(360, 640), textScale: 2);
      await app.start(tester);

      app.push.received.add(
        const PushNotice(title: 'Gone', eventId: 'e-404', opened: true),
      );
      await app.settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Back to Inbox'), findsOneWidget);
    });
  });

  group('notices about a device', () {
    testWidgets('4n: a tapped one opens the Devices screen, not an event', (
      tester,
    ) async {
      final app = FirstRunHarness(role: 'ADMIN', step: OnboardingStep.done);
      app.backend.publish('e-1', 'Build failed');
      useDesignPhone(tester);
      await app.start(tester);

      app.push.received.add(
        const PushNotice(
          title: 'New device paired',
          body: '"Rui - iPhone" can now read your SignalHub events.',
          opened: true,
          data: {'notice': 'client-paired', 'clientId': 'c-9'},
        ),
      );
      await app.settle(tester);

      expect(find.byType(DevicesScreen), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Event'), findsNothing);
    });

    testWidgets('one that arrives while the app is open adds no inbox row', (
      tester,
    ) async {
      final app = harness();
      app.backend.publish('e-1', 'Build failed');
      useDesignPhone(tester);
      await app.start(tester);

      app.push.received.add(
        const PushNotice(
          title: 'Device revoked',
          data: {'notice': 'client-revoked', 'clientId': 'c-9'},
        ),
      );
      await app.settle(tester);

      expect(find.byType(DevicesScreen), findsNothing);
      expect(app.controller.events.map((e) => e.title), ['Build failed']);
    });

    testWidgets('an event push still opens that event', (tester) async {
      final app = harness();
      app.backend.publish('e-1', 'Build failed');
      useDesignPhone(tester);
      await app.start(tester);

      app.push.received.add(
        const PushNotice(
          title: 'Build failed',
          eventId: 'e-1',
          opened: true,
          data: {'eventId': 'e-1', 'category': 'BLOCKED', 'severity': 'HIGH'},
        ),
      );
      await app.settle(tester);

      expect(find.widgetWithText(AppBar, 'Event'), findsOneWidget);
      expect(find.byType(DevicesScreen), findsNothing);
    });

    test('a push is a notice only by its data', () {
      expect(
        const PushNotice(title: 'x', data: {'notice': 'client-paired'}).notice,
        'client-paired',
      );
      expect(const PushNotice(title: 'x', eventId: 'e-1').notice, isNull);
    });
  });
}
