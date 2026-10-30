import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/models/event.dart';
import 'package:signalhub_client/src/ui/event_style.dart';

import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/phone.dart';

/// The inbox with questions: the chips, the line of each row and the dot on
/// the Inbox tab.
void main() {
  Finder byKey(String key) => find.byKey(Key(key));

  final merge = FakeBackend.question(
    choices: [('merge', 'Merge', null), ('hold', 'Hold', null)],
  );

  /// The drawing's inbox: two questions to answer, one waiting for someone
  /// else, answered, closed, and a plain event.
  AppHarness inbox({bool plain = true}) {
    final app = AppHarness();
    final b = app.backend;
    if (plain) {
      b.publish(
        'e-9',
        'Nightly backup finished',
        category: 'COMPLETED',
        severity: 'LOW',
        readAt: '2026-09-25T12:10:00Z',
      );
    }
    b
      ..publish(
        'e-8',
        'Rotate the backup key?',
        category: 'ACTION_REQUIRED',
        severity: 'NORMAL',
        readAt: '2026-09-25T12:10:00Z',
        ask: merge,
      )
      ..publish(
        'e-7',
        'Deploy window for R80?',
        category: 'ACTION_REQUIRED',
        severity: 'NORMAL',
        readAt: '2026-09-25T12:10:00Z',
        ask: merge,
      )
      ..publish(
        'e-6',
        'Restart the proxy?',
        category: 'ACTION_REQUIRED',
        severity: 'NORMAL',
        readAt: '2026-09-25T12:10:00Z',
        ask: merge,
      )
      ..publish(
        'e-5',
        'Rotate the staging key?',
        category: 'ACTION_REQUIRED',
        severity: 'NORMAL',
        readAt: '2026-09-25T12:10:00Z',
        ask: FakeBackend.question(
          choices: [('a', 'A', null), ('b', 'B', null)],
          who: [('user-1', 'Rodrigo'), ('user-2', 'Ana')],
        ),
        canAnswer: false,
      )
      ..publish(
        'e-2',
        'Which backup should I restore?',
        category: 'BLOCKED',
        severity: 'HIGH',
        readAt: '2026-09-25T12:10:00Z',
        ask: merge,
      )
      ..publish(
        'e-1',
        'Merge R82 into main?',
        category: 'ACTION_REQUIRED',
        severity: 'HIGH',
        ask: FakeBackend.question(
          choices: [('merge', 'Merge', null), ('hold', 'Hold', null)],
          closesAt: DateTime.now()
              .toUtc()
              .add(const Duration(hours: 5))
              .toIso8601String(),
        ),
      );
    b
      ..answerBy('e-6', 'Ana', ['hold'])
      ..close('e-7', by: 'TIME')
      ..close('e-8');
    return app;
  }

  testWidgets('each question row says its state in words', (tester) async {
    final app = inbox();
    useDesignPhone(tester);
    await app.start(tester);

    expect(find.textContaining('To answer · Closes'), findsOneWidget);
    expect(find.text('To answer'), findsWidgets);
    expect(find.text('Waiting for Rodrigo or Ana'), findsOneWidget);
    expect(find.text('Ana answered · Hold'), findsOneWidget);
    expect(find.text('Closed · nobody answered'), findsOneWidget);
    expect(find.text('Closed by nightly-build'), findsOneWidget);
    // An event that asks nothing is a row as before.
    expect(find.byKey(const Key('questionLine')), findsNWidgets(6));
  });

  testWidgets('the chips: Unread, and To answer with its count', (
    tester,
  ) async {
    final app = inbox();
    useDesignPhone(tester);
    await app.start(tester);

    expect(byKey('chipUnread'), findsOneWidget);
    expect(byKey('chipToAnswer'), findsOneWidget);
    expect(find.text('To answer 2'), findsNothing);
    expect(
      find.descendant(of: byKey('chipToAnswer'), matching: find.text('2')),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(byKey('chipToAnswer')),
      matchesSemantics(
        label: 'To answer, 2',
        isButton: true,
        hasSelectedState: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );
  });

  testWidgets('To answer lists only the open questions to answer', (
    tester,
  ) async {
    final app = inbox();
    useDesignPhone(tester);
    await app.start(tester);

    await tester.tap(byKey('chipToAnswer'));
    await app.settle(tester);

    expect(
      app.backend.requests
          .lastWhere((r) => r.url.path == '/api/v1/events')
          .url
          .queryParameters['toAnswer'],
      'true',
    );
    expect(find.text('Merge R82 into main?'), findsOneWidget);
    expect(find.text('Which backup should I restore?'), findsOneWidget);
    expect(find.text('Nightly backup finished'), findsNothing);
    expect(find.text('Restart the proxy?'), findsNothing);
    // Not a producer, category or severity: no grey bar of filters.
    expect(byKey('activeFilters'), findsNothing);
    expect(tester.widget<FilterChip>(byKey('chipToAnswer')).selected, isTrue);
  });

  testWidgets('with nothing left to answer, Show all events switches it off', (
    tester,
  ) async {
    final app = inbox();
    useDesignPhone(tester);
    await app.start(tester);
    await tester.tap(byKey('chipToAnswer'));
    await app.settle(tester);

    app.backend
      ..answerBy('e-1', 'Ana', ['hold'])
      ..answerBy('e-2', 'Ana', ['hold']);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 300));
    await app.settle(tester);

    expect(find.text('Nothing to answer'), findsOneWidget);
    expect(
      find.text(
        'Questions you can answer show up here until someone answers them or '
        'they close.',
      ),
      findsOneWidget,
    );
    // The chip stays while it is on, though its count is 0.
    expect(byKey('chipToAnswer'), findsOneWidget);
    await tester.tap(find.text('Show all events'));
    await app.settle(tester);

    expect(find.text('Nightly backup finished'), findsOneWidget);
    // Off and nothing to answer: the chip is gone.
    expect(byKey('chipToAnswer'), findsNothing);
  });

  testWidgets('the To answer view keeps the app bar as drawn (3b and 3c)', (
    tester,
  ) async {
    final app = inbox();
    useDesignPhone(tester);
    await app.start(tester);
    await tester.tap(byKey('chipToAnswer'));
    await app.settle(tester);

    // The chip is not one of the Filter sheet's filters: the icon stays
    // outlined, and Mark all as read is there but off.
    void expectBar() {
      expect(tester.widget<IconButton>(byKey('filter')).isSelected, isFalse);
      expect(find.byIcon(Icons.filter_list), findsOneWidget);
      expect(find.byIcon(Icons.filter_alt), findsNothing);
      expect(byKey('markAllRead'), findsOneWidget);
      expect(tester.widget<IconButton>(byKey('markAllRead')).onPressed, isNull);
    }

    expectBar();
    app.backend
      ..answerBy('e-1', 'Ana', ['hold'])
      ..answerBy('e-2', 'Ana', ['hold']);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 300));
    await app.settle(tester);

    expect(find.text('Nothing to answer'), findsOneWidget);
    expectBar();
  });

  testWidgets('the filter icon fills for the Filter sheet\'s filters', (
    tester,
  ) async {
    final app = inbox();
    useDesignPhone(tester);
    await app.start(tester);
    expect(tester.widget<IconButton>(byKey('filter')).isSelected, isFalse);

    await tester.tap(byKey('chipUnread'));
    await app.settle(tester);
    expect(tester.widget<IconButton>(byKey('filter')).isSelected, isTrue);
    expect(find.byIcon(Icons.filter_alt), findsOneWidget);
  });

  testWidgets('a person who never gets questions never sees To answer', (
    tester,
  ) async {
    final app = AppHarness();
    app.backend.publish('e-1', 'Plain event');
    useDesignPhone(tester);
    await app.start(tester);

    expect(byKey('chipUnread'), findsOneWidget);
    expect(byKey('chipToAnswer'), findsNothing);
  });

  testWidgets('the empty inbox shows no chips', (tester) async {
    final app = AppHarness();
    useDesignPhone(tester);
    await app.start(tester);

    expect(byKey('chipUnread'), findsNothing);
  });

  testWidgets('Unread is the filter sheet\'s switch', (tester) async {
    final app = inbox();
    useDesignPhone(tester);
    await app.start(tester);

    await tester.tap(byKey('chipUnread'));
    await app.settle(tester);

    expect(app.controller.filter.unreadOnly, isTrue);
    await tester.tap(byKey('filter'));
    await app.settle(tester);
    expect(tester.widget<SwitchListTile>(byKey('unreadOnly')).value, isTrue);
  });

  testWidgets('Mark all as read is off while To answer narrows the list', (
    tester,
  ) async {
    final app = inbox();
    useDesignPhone(tester);
    await app.start(tester);

    expect(app.controller.canMarkAllRead, isTrue);
    await tester.tap(byKey('chipToAnswer'));
    await app.settle(tester);
    expect(app.controller.canMarkAllRead, isFalse);
  });

  testWidgets('an open question stays in To answer after it is read', (
    tester,
  ) async {
    final app = inbox();
    useDesignPhone(tester);
    await app.start(tester);

    await tester.tap(find.text('Merge R82 into main?'));
    await app.settle(tester);
    expect(app.backend.isRead('e-1'), isTrue);
    await tester.pageBack();
    await app.settle(tester);

    expect(app.controller.toAnswerCount, 2);
  });

  group('the Inbox tab', () {
    String? nameOf(WidgetTester tester) {
      final node = tester.getSemantics(byKey('tab-inbox'));
      return node.label;
    }

    testWidgets('names its unread and what waits, with the number', (
      tester,
    ) async {
      final app = inbox();
      useDesignPhone(tester);
      final semantics = tester.ensureSemantics();
      await app.start(tester);

      expect(byKey('unreadCount'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Inbox, 1 unread, 2 to answer')),
        findsWidgets,
      );
      semantics.dispose();
    });

    testWidgets('with nothing unread, questions make it a dot', (tester) async {
      final app = inbox();
      app.backend.events.first['readAt'] = '2026-09-25T12:10:00Z';
      useDesignPhone(tester);
      final semantics = tester.ensureSemantics();
      await app.start(tester);

      expect(byKey('unreadCount'), findsNothing);
      expect(byKey('toAnswerDot'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Inbox, 2 to answer')), findsWidgets);
      expect(tester.widget<Badge>(byKey('toAnswerDot')).label, isNull);
      semantics.dispose();
    });

    testWidgets('with neither, it is only Inbox', (tester) async {
      final app = AppHarness();
      app.backend.publish(
        'e-1',
        'Read already',
        readAt: '2026-09-25T12:10:00Z',
      );
      useDesignPhone(tester);
      await app.start(tester);

      expect(byKey('unreadCount'), findsNothing);
      expect(byKey('toAnswerDot'), findsNothing);
      expect(nameOf(tester), contains('Inbox'));
    });
  });

  test('the Action required icon is pending_actions', () {
    expect(EventCategory.actionRequired.icon, Icons.pending_actions);
  });
}
