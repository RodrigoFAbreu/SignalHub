import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/app_controller.dart';
import 'package:signalhub_client/src/ui/event_screen.dart';
import 'package:signalhub_client/src/ui/inbox_screen.dart';
import 'package:signalhub_client/src/ui/producer_events_screen.dart';

import '../support/harness.dart';
import '../support/phone.dart';
import '../support/screenshot.dart';

void main() {
  setUpAll(loadDesignFonts);

  const ci = {'id': 'p-ci', 'name': 'ci-pipeline'};
  const backup = {'id': 'p-backup', 'name': 'backup-jobs'};

  /// Opens the events of `ci-pipeline` over the Producers tab of a device of
  /// [role], as the producer's screen does.
  Future<AppHarness> open(
    WidgetTester tester, {
    String role = 'BASIC',
    void Function(AppHarness)? fill,
    String id = 'p-ci',
    String name = 'ci-pipeline',
    Size size = const Size(412, 892),
    double textScale = 1,
    Brightness brightness = Brightness.dark,
  }) async {
    final app = AppHarness(role: role);
    fill?.call(app);
    useDesignPhone(
      tester,
      size: size,
      textScale: textScale,
      brightness: brightness,
    );
    await app.start(tester);
    await app.openTab(tester, HomeTab.producers);
    // The producer's screen, which is another worker's, pushes it so.
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => ProducerEventsScreen(
              controller: app.controller,
              producerId: id,
              producerName: name,
              openLink: (link) async {
                app.openedLinks.add(link);
                return true;
              },
            ),
          ),
        );
    await app.settle(tester);
    return app;
  }

  void sample(AppHarness app) => app.backend
    ..publish('e1', 'Old backup', producer: backup)
    ..publish(
      'e2',
      'Build 412 passed',
      producer: ci,
      category: 'INFO',
      severity: 'NORMAL',
      readAt: '2026-09-25T12:10:00Z',
    )
    ..publish(
      'e3',
      'Deploy to staging done',
      producer: ci,
      category: 'COMPLETED',
      severity: 'LOW',
      readAt: '2026-09-25T12:10:00Z',
    )
    ..publish('e4', 'Disk almost full', producer: backup)
    ..publish(
      'e5',
      'Your action: approve the release',
      producer: ci,
      category: 'ACTION_REQUIRED',
      severity: 'HIGH',
    );

  Finder chipX(String name) => find.byTooltip('Remove filter $name');

  for (final role in ['BASIC', 'MOD', 'ADMIN']) {
    testWidgets('a $role sees the producer\'s events only', (tester) async {
      await open(tester, role: role, fill: sample);

      expect(find.widgetWithText(AppBar, 'ci-pipeline'), findsOneWidget);
      expect(find.text('Events from this producer'), findsOneWidget);
      expect(find.text('Your action: approve the release'), findsOneWidget);
      expect(find.text('Build 412 passed'), findsOneWidget);
      expect(find.text('Deploy to staging done'), findsOneWidget);
      expect(find.text('Disk almost full'), findsNothing);
      expect(find.text('Old backup'), findsNothing);
    });
  }

  testWidgets('has the filter and mark all as read icons, and Back', (
    tester,
  ) async {
    await open(tester, fill: sample);

    expect(find.byTooltip('Filter events'), findsOneWidget);
    expect(find.byTooltip('Mark all as read'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
  });

  testWidgets('Back returns to where it was opened from', (tester) async {
    final app = await open(tester, fill: sample);

    await tester.tap(find.byTooltip('Back'));
    await app.settle(tester);

    expect(find.byType(ProducerEventsScreen), findsNothing);
    expect(find.widgetWithText(AppBar, 'Producers'), findsOneWidget);
  });

  group('the producer chip', () {
    testWidgets('is selected, named, and its x is 48 dp', (tester) async {
      final semantics = tester.ensureSemantics();
      await open(tester, fill: sample);

      expect(find.byKey(const Key('producerChip')), findsOneWidget);
      expect(
        find.bySemanticsLabel('Remove filter ci-pipeline'),
        findsOneWidget,
      );
      final x = find.ancestor(
        of: find.byIcon(Icons.close),
        matching: find.byType(SizedBox),
      );
      expect(tester.getSize(x.first), const Size(48, 48));
      semantics.dispose();
    });

    testWidgets('removing it leaves for the full inbox', (tester) async {
      final app = await open(tester, fill: sample);
      expect(app.controller.tab, HomeTab.producers);

      await tester.tap(chipX('ci-pipeline'));
      await app.settle(tester);

      expect(find.byType(ProducerEventsScreen), findsNothing);
      expect(app.controller.tab, HomeTab.inbox);
      // The inbox is whole: every producer's events, no filter.
      expect(find.byType(InboxScreen), findsOneWidget);
      expect(find.text('Disk almost full'), findsOneWidget);
      expect(find.text('Your action: approve the release'), findsOneWidget);
      expect(app.controller.filter.isActive, isFalse);
    });

    testWidgets('a long name ends in an ellipsis at 360 dp and 200 %', (
      tester,
    ) async {
      await open(
        tester,
        id: 'p-long',
        name: 'quarterly-finance-report-generator-for-the-whole-company',
        size: const Size(360, 800),
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
      expect(
        chipX('quarterly-finance-report-generator-for-the-whole-company'),
        findsOneWidget,
      );
    });
  });

  group('filters', () {
    Future<void> openSheet(WidgetTester tester, AppHarness app) async {
      await tester.tap(find.byTooltip('Filter events'));
      await app.settle(tester);
    }

    testWidgets('unread only narrows the list, and shows as a chip', (
      tester,
    ) async {
      final app = await open(tester, fill: sample);
      await openSheet(tester, app);

      await tester.tap(find.byKey(const Key('unreadOnly')));
      await app.settle(tester);

      expect(find.text('Your action: approve the release'), findsOneWidget);
      expect(find.text('Build 412 passed'), findsNothing);
      expect(find.text('Unread'), findsOneWidget);
      // The Inbox tab's own filter is left alone.
      expect(app.controller.filter.isActive, isFalse);
    });

    testWidgets('categories and severities combine with the producer', (
      tester,
    ) async {
      final app = await open(tester, fill: sample);
      await openSheet(tester, app);

      await tester.tap(find.byKey(const Key('filterCategory-COMPLETED')));
      await app.settle(tester);

      expect(find.text('Deploy to staging done'), findsOneWidget);
      expect(find.text('Build 412 passed'), findsNothing);

      await tester.tap(find.byKey(const Key('filterSeverity-HIGH')));
      await app.settle(tester);

      expect(find.text('No events match these filters'), findsOneWidget);
      expect(find.text('Disk almost full'), findsNothing);
    });

    testWidgets('a filter chip is removed with its x', (tester) async {
      final app = await open(tester, fill: sample);
      await openSheet(tester, app);
      await tester.tap(find.byKey(const Key('filterCategory-COMPLETED')));
      await app.settle(tester);
      await tester.tapAt(const Offset(10, 10));
      await app.settle(tester);
      expect(find.text('Build 412 passed'), findsNothing);

      await tester.tap(chipX('Completed'));
      await app.settle(tester);

      expect(find.text('Build 412 passed'), findsOneWidget);
      expect(find.byType(ProducerEventsScreen), findsOneWidget);
    });

    testWidgets('the filter icon shows when one is on', (tester) async {
      final app = await open(tester, fill: sample);
      expect(find.byIcon(Icons.filter_alt), findsNothing);
      await openSheet(tester, app);

      await tester.tap(find.byKey(const Key('unreadOnly')));
      await app.settle(tester);
      await tester.tapAt(const Offset(10, 10));
      await app.settle(tester);

      expect(find.byIcon(Icons.filter_alt), findsOneWidget);
    });

    testWidgets('Clear all clears them', (tester) async {
      final app = await open(tester, fill: sample);
      await openSheet(tester, app);
      await tester.tap(find.byKey(const Key('unreadOnly')));
      await app.settle(tester);

      await tester.tap(find.byKey(const Key('clearFiltersInSheet')));
      await app.settle(tester);

      expect(find.text('Build 412 passed'), findsOneWidget);
    });
  });

  group('when there is nothing to show', () {
    testWidgets('no events yet', (tester) async {
      final app = await open(tester, id: 'p-new', name: 'garage-door');

      expect(find.text('No events from garage-door yet'), findsOneWidget);
      expect(find.text('When it sends one, it shows up here.'), findsOneWidget);
      await tester.tap(find.text('Back to garage-door'));
      await app.settle(tester);
      expect(find.byType(ProducerEventsScreen), findsNothing);
    });

    testWidgets('nothing unread offers Show all', (tester) async {
      final app = await open(
        tester,
        fill: (app) => app.backend.publish(
          'e1',
          'Done',
          producer: ci,
          readAt: '2026-09-25T12:10:00Z',
        ),
      );
      await tester.tap(find.byTooltip('Filter events'));
      await app.settle(tester);
      await tester.tap(find.byKey(const Key('unreadOnly')));
      await app.settle(tester);
      await tester.tapAt(const Offset(10, 10));
      await app.settle(tester);

      expect(find.text('Nothing unread from ci-pipeline.'), findsOneWidget);

      await tester.tap(find.text('Show all'));
      await app.settle(tester);

      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('a list that did not load can be tried again', (tester) async {
      final app = AppHarness();
      app.backend.publish('e1', 'Build', producer: ci);
      useDesignPhone(tester);
      await app.start(tester);
      app.backend.offline = true;
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .push(
            MaterialPageRoute<void>(
              builder: (_) => ProducerEventsScreen(
                controller: app.controller,
                producerId: 'p-ci',
                producerName: 'ci-pipeline',
              ),
            ),
          );
      await app.settle(tester);

      expect(find.text("Couldn't load events"), findsOneWidget);
      expect(find.text('Check your connection and try again.'), findsOneWidget);

      app.backend.offline = false;
      await tester.tap(find.text('Try again'));
      await app.settle(tester);

      expect(find.text('Build'), findsOneWidget);
    });

    testWidgets('pulling down reads the list again', (tester) async {
      final app = await open(tester, fill: sample);
      expect(find.text('New build'), findsNothing);

      app.backend.publish('e6', 'New build', producer: ci);
      await tester.fling(
        find.byType(ListView).first,
        const Offset(0, 400),
        1000,
      );
      await app.settle(tester);

      expect(find.text('New build'), findsOneWidget);
    });
  });

  group('read state', () {
    testWidgets('opening an event reads it here and in the inbox', (
      tester,
    ) async {
      final app = await open(tester, fill: sample);
      expect(app.controller.unreadCount, 3);

      await tester.tap(find.text('Your action: approve the release'));
      await app.settle(tester);
      expect(find.byType(EventScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await app.settle(tester);

      expect(app.backend.isRead('e5'), isTrue);
      expect(app.controller.unreadCount, 2);
      expect(find.byKey(const Key('unread')), findsNothing);
    });

    testWidgets('marking an event unread brings the dot back', (tester) async {
      final app = await open(tester, fill: sample);

      await tester.tap(find.text('Build 412 passed'));
      await app.settle(tester);
      await tester.tap(find.byKey(const Key('markUnread')));
      await app.settle(tester);

      expect(app.backend.isRead('e2'), isFalse);
      expect(find.byKey(const Key('unread')), findsNWidgets(2));
    });

    testWidgets('mark all as read reads this producer\'s events only', (
      tester,
    ) async {
      final app = await open(tester, fill: sample);

      await tester.tap(find.byTooltip('Mark all as read'));
      await app.settle(tester);

      expect(app.backend.isRead('e5'), isTrue);
      expect(app.backend.isRead('e4'), isFalse);
      expect(app.backend.isRead('e1'), isFalse);
      expect(find.byKey(const Key('unread')), findsNothing);
      // The count on the inbox follows.
      expect(app.controller.unreadCount, 2);
      // And nothing is left for it to mark.
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('markAllRead')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('mark all as read is off when nothing is unread', (
      tester,
    ) async {
      await open(
        tester,
        fill: (app) => app.backend.publish(
          'e1',
          'Done',
          producer: ci,
          readAt: '2026-09-25T12:10:00Z',
        ),
      );

      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('markAllRead')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('mark all as read says when it failed', (tester) async {
      final app = await open(tester, fill: sample);
      app.backend.offline = true;

      await tester.tap(find.byTooltip('Mark all as read'));
      await app.settle(tester);

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.byKey(const Key('unread')), findsOneWidget);
    });

    testWidgets('an event with a link opens it from its screen', (
      tester,
    ) async {
      final app = await open(
        tester,
        fill: (app) => app.backend.publish(
          'e1',
          'Approve it',
          producer: ci,
          link: 'https://ci.example/run/7',
        ),
      );

      await tester.tap(find.text('Approve it'));
      await app.settle(tester);
      await tester.tap(find.text('Open link'));
      await app.settle(tester);

      expect(app.openedLinks.single.toString(), 'https://ci.example/run/7');
    });
  });

  testWidgets('older events are read as the list scrolls', (tester) async {
    final app = await open(
      tester,
      fill: (app) {
        for (var i = 1; i <= 35; i++) {
          app.backend.publish('e$i', 'Event $i', producer: ci);
        }
      },
    );
    expect(find.text('Event 35'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Event 1'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    await app.settle(tester);

    expect(find.text('Event 1'), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    testWidgets('360 dp, 200 % text, $brightness, without overflow', (
      tester,
    ) async {
      await open(
        tester,
        fill: sample,
        size: const Size(360, 800),
        textScale: 2,
        brightness: brightness,
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(EventTile), findsWidgets);
    });
  }

  testWidgets('the empty state at 200 % does not overflow', (tester) async {
    await open(
      tester,
      id: 'p-new',
      name: 'garage-door',
      size: const Size(360, 800),
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
  });
}
