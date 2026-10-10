import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/app_controller.dart';
import 'package:signalhub_client/src/ui/new_producer_screen.dart';
import 'package:signalhub_client/src/ui/producer_screen.dart';
import 'package:signalhub_client/src/ui/widgets/bell_toggle.dart';
import 'package:signalhub_client/src/ui/widgets/skeleton.dart';
import 'package:signalhub_client/src/ui/widgets/tags.dart';

import '../support/harness.dart';
import '../support/phone.dart';
import '../support/producers_backend.dart';
import '../support/screenshot.dart';

void main() {
  setUpAll(loadDesignFonts);

  Finder bell(String name) =>
      find.byWidgetPredicate((w) => w is BellToggle && w.name == name);

  Finder chip(String key) => find.byKey(Key('producerFilter-$key'));

  /// Taps a chip, scrolling the strip to it first.
  Future<void> tapChip(WidgetTester tester, String key) async {
    await tester.ensureVisible(chip(key));
    await tester.tap(chip(key));
    await tester.pump();
    // The scaffold lets a button that goes finish its own short exit.
    await tester.pump(const Duration(milliseconds: 300));
  }

  Finder newProducerButton() => find.text('New producer');

  /// Opens the Producers tab of a device of [role], with [fill] on the server.
  Future<(AppHarness, FakeProducers)> open(
    WidgetTester tester, {
    String role = 'BASIC',
    void Function(FakeProducers)? fill,
    Size size = const Size(412, 892),
    double textScale = 1,
    Brightness brightness = Brightness.dark,
  }) async {
    final app = AppHarness(role: role);
    final server = FakeProducers(app.backend);
    fill?.call(server);
    useDesignPhone(
      tester,
      size: size,
      textScale: textScale,
      brightness: brightness,
    );
    await app.start(tester);
    await app.openTab(tester, HomeTab.producers);
    return (app, server);
  }

  void listOfEveryKind(FakeProducers s) => s
    ..addOwn('o1', 'ci-pipeline', keys: 2, lastEventAt: todayAt(1, 19))
    ..addOwn('o2', 'garage-door', paused: true)
    ..addVisible('v1', 'family-calendar', private: true)
    ..addVisible('v2', 'ana-reports')
    ..addVisible('v3', 'price-watch', owner: 'João', subscribed: false);

  for (final role in ['BASIC', 'MOD', 'ADMIN']) {
    testWidgets('a $role sees the tab, its list and the New producer button', (
      tester,
    ) async {
      await open(tester, role: role, fill: listOfEveryKind);

      expect(find.widgetWithText(AppBar, 'Producers'), findsOneWidget);
      expect(find.text('Find a producer'), findsOneWidget);
      for (final name in [
        'ci-pipeline',
        'garage-door',
        'ana-reports',
        'family-calendar',
        'price-watch',
      ]) {
        expect(find.text(name), findsOneWidget);
      }
      expect(newProducerButton(), findsOneWidget);
    });
  }

  testWidgets('every kind of row says what it is', (tester) async {
    await open(
      tester,
      fill: (s) => s
        ..addOwn('o1', 'ci-pipeline', keys: 2, lastEventAt: todayAt(1, 19))
        ..addOwn('o2', 'garage-door', paused: true)
        ..addOwn('o3', 'old-sensor', disabledByHost: true)
        ..addVisible('v1', 'family-calendar', private: true)
        ..addVisible('v2', 'weather-alerts', owner: 'João', disabled: true)
        ..addVisible('v3', 'price-watch', owner: 'João', subscribed: false),
    );

    expect(find.text('Public · 2 keys · last event 01:19'), findsOneWidget);
    expect(find.text('Paused by you · its keys do not work'), findsOneWidget);
    expect(find.text('Disabled by the host · ask the host'), findsOneWidget);
    expect(find.text('Ana · Private, shared with you'), findsOneWidget);
    expect(find.text('João · Disabled'), findsOneWidget);
    expect(find.text('João · Public'), findsOneWidget);
    // The host's disabling is in the error colour, the rest is not.
    final colors = Theme.of(tester.element(find.text('ci-pipeline')))
        .colorScheme;
    Color? colorOf(String text) =>
        tester.widget<Text>(find.text(text)).style?.color;
    expect(colorOf('Disabled by the host · ask the host'), colors.error);
    expect(
      colorOf('Paused by you · its keys do not work'),
      colors.onSurfaceVariant,
    );
    // Yours carries a tag, nobody else's does.
    expect(find.byType(LabelTag), findsNWidgets(3));
  });

  testWidgets('a producer this device mutes says so', (tester) async {
    final app = AppHarness();
    app.backend.pushPreferences = {
      ...?app.backend.pushPreferences,
      'mutedProducerIds': ['v2'],
    };
    FakeProducers(app.backend)
      ..addVisible('v2', 'ana-reports')
      ..addVisible('v3', 'price-watch', subscribed: false);
    useDesignPhone(tester);
    await app.start(tester);
    await app.openTab(tester, HomeTab.producers);

    expect(find.text('Ana · Public · Muted on this device'), findsOneWidget);
    expect(find.text('Ana · Public'), findsOneWidget);
  });

  testWidgets('lists Yours, then Subscribed, then Can subscribe, each A to Z', (
    tester,
  ) async {
    await open(
      tester,
      fill: (s) => s
        ..addVisible('a', 'weather-alerts', subscribed: false)
        ..addVisible('b', 'zebra')
        ..addVisible('c', 'Ana-reports')
        ..addOwn('d', 'quarterly', subscribed: false)
        ..addOwn('e', 'backup-jobs'),
    );

    double top(String name) => tester.getTopLeft(find.text(name)).dy;
    final order = [
      'backup-jobs',
      'quarterly',
      'Ana-reports',
      'zebra',
      'weather-alerts',
    ];
    for (var i = 1; i < order.length; i++) {
      expect(top(order[i]), greaterThan(top(order[i - 1])), reason: order[i]);
    }
  });

  group('the chips', () {
    testWidgets('are single choice, with a check on the selected one', (
      tester,
    ) async {
      await open(tester, fill: listOfEveryKind);

      bool selected(String key) =>
          tester.widget<FilterChip>(chip(key)).selected;
      expect(
        [
          for (final k in ['all', 'yours', 'subscribed', 'canSubscribe'])
            selected(k),
        ],
        [true, false, false, false],
      );
      expect(tester.widget<FilterChip>(chip('all')).showCheckmark, isTrue);

      await tapChip(tester, 'yours');

      expect(
        [
          for (final k in ['all', 'yours', 'subscribed', 'canSubscribe'])
            selected(k),
        ],
        [false, true, false, false],
      );
    });

    testWidgets('narrow the list', (tester) async {
      await open(tester, fill: listOfEveryKind);

      await tapChip(tester, 'yours');
      expect(find.text('ci-pipeline'), findsOneWidget);
      expect(find.text('garage-door'), findsOneWidget);
      expect(find.text('ana-reports'), findsNothing);

      await tapChip(tester, 'subscribed');
      expect(find.text('ana-reports'), findsOneWidget);
      expect(find.text('ci-pipeline'), findsOneWidget);
      expect(find.text('price-watch'), findsNothing);

      await tapChip(tester, 'canSubscribe');
      expect(find.text('price-watch'), findsOneWidget);
      expect(find.text('ana-reports'), findsNothing);

      await tapChip(tester, 'all');
      expect(find.text('ana-reports'), findsOneWidget);
      expect(find.text('price-watch'), findsOneWidget);
    });

    testWidgets('have a 48 dp hit area and scroll sideways', (tester) async {
      await open(
        tester,
        fill: listOfEveryKind,
        size: const Size(360, 800),
        textScale: 2,
      );

      expect(tester.getSize(chip('all')).height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
      // The last chip is past the edge, and still one scroll away.
      await tester.dragUntilVisible(
        chip('canSubscribe'),
        find.byType(SingleChildScrollView).first,
        const Offset(-100, 0),
      );
      expect(chip('canSubscribe'), findsOneWidget);
    });
  });

  group('search', () {
    testWidgets('finds a producer by part of its name', (tester) async {
      await open(tester, fill: listOfEveryKind);

      await tester.enterText(find.byType(TextField), 'ANA');
      await tester.pump();

      expect(find.text('ana-reports'), findsOneWidget);
      expect(find.text('ci-pipeline'), findsNothing);
    });

    testWidgets('says when nothing matches, keeps the chips and the button', (
      tester,
    ) async {
      await open(tester, fill: listOfEveryKind);

      await tester.enterText(find.byType(TextField), 'zebra');
      await tester.pump();

      expect(find.text('No producers match'), findsOneWidget);
      expect(
        find.text(
          'Nothing you can see is named “zebra”. '
          'Check the spelling, or clear the search.',
        ),
        findsOneWidget,
      );
      expect(chip('all'), findsOneWidget);
      expect(newProducerButton(), findsOneWidget);

      await tester.tap(find.text('Clear search'));
      await tester.pump();

      expect(find.text('ci-pipeline'), findsOneWidget);
      expect(find.text('No producers match'), findsNothing);
    });

    testWidgets('has a Clear search button once something is typed', (
      tester,
    ) async {
      await open(tester, fill: listOfEveryKind);
      expect(find.byTooltip('Clear search'), findsNothing);

      await tester.enterText(find.byType(TextField), 'ana');
      await tester.pump();
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();

      expect(find.text('ci-pipeline'), findsOneWidget);
    });
  });

  group('empty states', () {
    testWidgets('no producer at all: one New producer button, in the state', (
      tester,
    ) async {
      await open(tester);

      expect(find.text('No producers yet'), findsOneWidget);
      expect(
        find.text(
          'Nobody has shared a producer with you, and there is no public one '
          'on this server. Make your own to send yourself events.',
        ),
        findsOneWidget,
      );
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(newProducerButton(), findsOneWidget);
      expect(chip('all'), findsOneWidget);
    });

    testWidgets('nothing under Yours', (tester) async {
      await open(tester, fill: (s) => s.addVisible('v', 'ana-reports'));

      await tapChip(tester, 'yours');

      expect(find.text("You don't have a producer yet"), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(newProducerButton(), findsOneWidget);
    });

    testWidgets('nothing under Subscribed offers Show all', (tester) async {
      await open(
        tester,
        fill: (s) => s.addVisible('v', 'price-watch', subscribed: false),
      );

      await tapChip(tester, 'subscribed');

      expect(
        find.text("You aren't subscribed to any producer"),
        findsOneWidget,
      );
      expect(find.byType(FloatingActionButton), findsOneWidget);
      await tester.tap(find.text('Show all'));
      await tester.pump();
      expect(find.text('price-watch'), findsOneWidget);
      expect(tester.widget<FilterChip>(chip('all')).selected, isTrue);
    });

    testWidgets('nothing under Can subscribe keeps the corner button', (
      tester,
    ) async {
      await open(tester, fill: (s) => s.addVisible('v', 'ana-reports'));

      await tapChip(tester, 'canSubscribe');

      expect(find.text('Nothing else to subscribe to'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      await tester.tap(find.text('Show all'));
      await tester.pump();
      expect(find.text('ana-reports'), findsOneWidget);
    });

    testWidgets('the New producer button of the state opens its screen', (
      tester,
    ) async {
      final (app, _) = await open(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'New producer'));
      await app.settle(tester);

      expect(find.byType(NewProducerScreen), findsOneWidget);
    });
  });

  group('the bell', () {
    testWidgets('subscribes in place with a ring meanwhile, then says so', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final (app, server) = await open(
        tester,
        fill: (s) => s.addVisible('v', 'price-watch', subscribed: false),
      );
      server.holdSubscriptions = Completer();

      await tester.tap(bell('price-watch'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(const Key('bellRing')), findsOneWidget);
      expect(
        find.bySemanticsLabel('Subscribing to price-watch'),
        findsOneWidget,
      );
      // Taps are ignored while it runs.
      await tester.tap(bell('price-watch'));
      await tester.pump();
      expect(server.subscriptionCalls, ['PUT v']);

      server.holdSubscriptions!.complete();
      await app.settle(tester);

      expect(find.byKey(const Key('bellRing')), findsNothing);
      expect(
        find.bySemanticsLabel(
          'Subscribed to price-watch. Double tap to unsubscribe.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Subscribed to price-watch. Its older events are in your inbox too.',
        ),
        findsOneWidget,
      );
      expect(find.text('Undo'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('unsubscribes with Undo, which subscribes again', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final (app, server) = await open(
        tester,
        fill: (s) => s.addVisible('v', 'ana-reports'),
      );

      await tester.tap(bell('ana-reports'));
      await app.settle(tester);

      expect(
        find.text(
          'Unsubscribed from ana-reports. Its events leave your inbox.',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Not subscribed to ana-reports. Double tap to subscribe.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Undo'));
      await app.settle(tester);

      expect(server.subscriptionCalls, ['DELETE v', 'PUT v']);
      expect(
        find.bySemanticsLabel(
          'Subscribed to ana-reports. Double tap to unsubscribe.',
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('moves between Subscribed and Can subscribe at once', (
      tester,
    ) async {
      final (app, _) = await open(
        tester,
        fill: (s) => s
          ..addVisible('a', 'zebra-reports')
          ..addVisible('b', 'ana-reports', subscribed: false),
      );
      double top(String name) => tester.getTopLeft(find.text(name)).dy;
      expect(top('zebra-reports'), lessThan(top('ana-reports')));

      await tester.tap(bell('zebra-reports'));
      await app.settle(tester);

      // Both can be subscribed to now: A to Z.
      expect(top('ana-reports'), lessThan(top('zebra-reports')));
    });

    testWidgets('a failure goes back and offers Retry', (tester) async {
      final (app, server) = await open(
        tester,
        fill: (s) => s.addVisible('v', 'price-watch', subscribed: false),
      );
      server.subscribeFailures['v'] = 500;

      await tester.tap(bell('price-watch'));
      await app.settle(tester);

      expect(
        find.text("Couldn't subscribe to price-watch. Try again."),
        findsOneWidget,
      );
      expect(
        tester.widget<BellToggle>(bell('price-watch')).subscribed,
        isFalse,
      );
      expect(tester.widget<BellToggle>(bell('price-watch')).changingTo, isNull);

      server.subscribeFailures.clear();
      await tester.tap(find.text('Retry'));
      await app.settle(tester);

      expect(tester.widget<BellToggle>(bell('price-watch')).subscribed, isTrue);
      expect(server.subscriptionCalls, ['PUT v', 'PUT v']);
    });

    testWidgets('a failure to unsubscribe says so', (tester) async {
      final (app, server) = await open(
        tester,
        fill: (s) => s.addVisible('v', 'ana-reports'),
      );
      server.subscribeFailures['v'] = null;

      await tester.tap(bell('ana-reports'));
      await app.settle(tester);

      expect(
        find.text("Couldn't unsubscribe from ana-reports. Try again."),
        findsOneWidget,
      );
      expect(tester.widget<BellToggle>(bell('ana-reports')).subscribed, isTrue);
    });

    testWidgets('a producer that is gone leaves the list', (tester) async {
      final (app, server) = await open(
        tester,
        fill: (s) => s
          ..addVisible('a', 'ana-reports')
          ..addVisible('b', 'price-watch'),
      );
      server.subscribeFailures['a'] = 404;

      await tester.tap(bell('ana-reports'));
      await app.settle(tester);

      expect(find.text('ana-reports'), findsNothing);
      expect(find.text('price-watch'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('paused and disabled producers keep the bell', (tester) async {
      await open(
        tester,
        fill: (s) => s
          ..addOwn('a', 'garage-door', paused: true)
          ..addOwn('b', 'old-sensor', disabledByHost: true)
          ..addVisible('c', 'weather-alerts', owner: 'João', disabled: true),
      );

      for (final name in ['garage-door', 'old-sensor', 'weather-alerts']) {
        expect(bell(name), findsOneWidget);
        expect(
          tester.widget<BellToggle>(bell(name)).onPressed,
          isNotNull,
          reason: name,
        );
      }
    });

    testWidgets('the inbox is read again, since its events changed', (
      tester,
    ) async {
      final (app, server) = await open(
        tester,
        fill: (s) => s.addVisible('v', 'price-watch', subscribed: false),
      );
      final before = app.backend.requests
          .where((r) => r.url.path == '/api/v1/events')
          .length;

      await tester.tap(bell('price-watch'));
      await app.settle(tester);

      final after = app.backend.requests
          .where((r) => r.url.path == '/api/v1/events')
          .length;
      expect(after, greaterThan(before));
      expect(server.subscriptionCalls, ['PUT v']);
    });

    testWidgets('a change by a bell does not disturb the others', (
      tester,
    ) async {
      final (app, server) = await open(
        tester,
        fill: (s) => s
          ..addVisible('a', 'ana-reports', subscribed: false)
          ..addVisible('b', 'price-watch', subscribed: false),
      );
      server.holdSubscriptions = Completer();

      await tester.tap(bell('ana-reports'));
      await tester.pump();
      // The rest of the list stays live.
      await tester.tap(bell('price-watch'));
      await tester.pump();

      expect(server.subscriptionCalls, ['PUT a', 'PUT b']);
      server.holdSubscriptions!.complete();
      await app.settle(tester);
    });
  });

  group('a row', () {
    testWidgets('opens the producer', (tester) async {
      final (app, _) = await open(tester, fill: listOfEveryKind);

      await tester.tap(find.text('ana-reports'));
      await app.settle(tester);

      final screen = tester.widget<ProducerScreen>(find.byType(ProducerScreen));
      expect(screen.producerId, 'v2');
    });

    testWidgets('is read again when the producer screen is left', (
      tester,
    ) async {
      final (app, server) = await open(tester, fill: listOfEveryKind);
      await tester.tap(find.text('ana-reports'));
      await app.settle(tester);
      final reads = server.visibleReads;

      server.visible.removeWhere((p) => p['id'] == 'v2');
      Navigator.of(tester.element(find.byType(ProducerScreen))).pop();
      await app.settle(tester);

      expect(server.visibleReads, greaterThan(reads));
      expect(find.text('ana-reports'), findsNothing);
    });

    testWidgets('ends a long name in an ellipsis, and the tag keeps its size', (
      tester,
    ) async {
      await open(
        tester,
        size: const Size(360, 800),
        fill: (s) => s
          ..addOwn('a', 'quarterly-finance-report-generator', private: true)
          ..addOwn('b', 'ci', keys: 2),
      );

      final longName = tester.widget<Text>(
        find.text('quarterly-finance-report-generator'),
      );
      expect(longName.overflow, TextOverflow.ellipsis);
      expect(longName.maxLines, 1);
      final tags = find.byType(LabelTag);
      expect(
        tester.getSize(tags.at(0)),
        tester.getSize(tags.at(1)),
        reason: 'the tag is the same beside a long name and a short one',
      );
      expect(tester.getSize(bell('ci')), const Size(48, 48));
      expect(
        tester.getSize(bell('quarterly-finance-report-generator')),
        const Size(48, 48),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('has a 48 dp bell target with a 40 dp circle', (tester) async {
      await open(tester, fill: (s) => s.addVisible('v', 'ana-reports'));

      expect(tester.getSize(bell('ana-reports')), const Size(48, 48));
      final circle = find.descendant(
        of: bell('ana-reports'),
        matching: find.byType(Container),
      );
      expect(tester.getSize(circle.first), const Size(40, 40));
    });
  });

  group('loading, failing and offline', () {
    testWidgets('shows skeleton rows while the first read runs', (
      tester,
    ) async {
      final app = AppHarness();
      final server = FakeProducers(app.backend)..holdLists = Completer();
      useDesignPhone(tester);
      await app.start(tester);

      await tester.tap(find.byKey(const Key('tab-producers')));
      await tester.pump();

      expect(find.byType(SkeletonRows), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(chip('all'), findsNothing);
      server.holdLists!.complete();
      await app.settle(tester);
      expect(find.byType(SkeletonRows), findsNothing);
    });

    testWidgets('a list that did not load says so, and Try again reads it', (
      tester,
    ) async {
      final (app, server) = await open(
        tester,
        fill: (s) => s
          ..addVisible('v', 'ana-reports')
          ..listFailure = 0,
      );

      expect(find.text("Couldn't load producers"), findsOneWidget);
      expect(find.text('Check your connection and try again.'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);

      server.listFailure = null;
      await tester.tap(find.text('Try again'));
      await app.settle(tester);

      expect(find.text('ana-reports'), findsOneWidget);
    });

    testWidgets('a server error is said as one', (tester) async {
      await open(tester, fill: (s) => s.listFailure = 500);

      expect(
        find.text('SignalHub had a problem. Try again in a moment.'),
        findsOneWidget,
      );
    });

    testWidgets('offline: the older list stays, writes are greyed once', (
      tester,
    ) async {
      final (app, server) = await open(
        tester,
        fill: (s) => s
          ..addVisible('a', 'ana-reports', subscribed: false)
          ..addOwn('o', 'ci-pipeline'),
      );
      server.listFailure = 0;

      await tester.runAsync(app.controller.producers.load);
      await app.settle(tester);

      expect(
        find.textContaining("You're offline. This is the list from "),
        findsOneWidget,
      );
      expect(
        find.textContaining("Changes are paused until you're back."),
        findsOneWidget,
      );
      // Reading still works.
      expect(find.text('ana-reports'), findsOneWidget);
      expect(find.text('ci-pipeline'), findsOneWidget);
      // Writes are greyed, and ignore taps.
      for (final name in ['ana-reports', 'ci-pipeline']) {
        expect(tester.widget<BellToggle>(bell(name)).onPressed, isNull);
      }
      await tester.tap(bell('ana-reports'), warnIfMissed: false);
      await tester.pump();
      expect(server.subscriptionCalls, isEmpty);
      final button = find.byType(FloatingActionButton);
      expect(tester.widget<FloatingActionButton>(button).onPressed, isNotNull);
      await tester.tap(button);
      await tester.pump();
      expect(find.byType(NewProducerScreen), findsNothing);

      // It clears itself when the list is read again.
      server.listFailure = null;
      await tester.runAsync(app.controller.producers.load);
      await app.settle(tester);

      expect(find.textContaining("You're offline"), findsNothing);
      expect(
        tester.widget<BellToggle>(bell('ana-reports')).onPressed,
        isNotNull,
      );
    });

    testWidgets(
      'a refresh that failed on the server keeps the list, with Try again',
      (tester) async {
        final (app, server) = await open(
          tester,
          fill: (s) => s.addVisible('a', 'ana-reports'),
        );
        server.listFailure = 500;
        await tester.runAsync(app.controller.producers.load);
        await app.settle(tester);

        expect(
          find.textContaining("Couldn't refresh the list."),
          findsOneWidget,
        );
        expect(find.text('ana-reports'), findsOneWidget);

        server.listFailure = null;
        await tester.tap(find.text('Try again'));
        await app.settle(tester);

        expect(find.textContaining("Couldn't refresh"), findsNothing);
      },
    );

    testWidgets('pull to refresh reads the lists again', (tester) async {
      final (app, server) = await open(tester, fill: listOfEveryKind);
      final reads = server.visibleReads;

      server.addVisible('n', 'new-one');
      await tester.fling(
        find.byType(ListView).first,
        const Offset(0, 400),
        1000,
      );
      await app.settle(tester);

      expect(server.visibleReads, greaterThan(reads));
      expect(find.text('new-one'), findsOneWidget);
    });

    testWidgets('is read again each time the tab is opened', (tester) async {
      final (app, server) = await open(tester, fill: listOfEveryKind);
      final reads = server.visibleReads;

      await app.openTab(tester, HomeTab.inbox);
      expect(server.visibleReads, reads);
      server.visible.removeWhere((p) => p['id'] == 'v2');
      await app.openTab(tester, HomeTab.producers);

      expect(server.visibleReads, reads + 1);
      expect(find.text('ana-reports'), findsNothing);
    });

    testWidgets('a producer the user lost access to just disappears', (
      tester,
    ) async {
      final (app, server) = await open(tester, fill: listOfEveryKind);
      expect(find.text('family-calendar'), findsOneWidget);

      server.visible.removeWhere((p) => p['id'] == 'v1');
      await tester.runAsync(app.controller.producers.load);
      await app.settle(tester);

      expect(find.text('family-calendar'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('ana-reports'), findsOneWidget);
    });
  });

  group('the New producer button', () {
    testWidgets('opens its screen, 16 dp above the bar', (tester) async {
      final (app, _) = await open(tester, fill: listOfEveryKind);
      final bar = tester.getRect(find.byKey(const Key('tab-producers')));
      final button = tester.getRect(find.byType(FloatingActionButton));
      expect(bar.top - button.bottom, closeTo(16, 0.5));

      await tester.tap(newProducerButton());
      await app.settle(tester);

      expect(find.byType(NewProducerScreen), findsOneWidget);
    });

    testWidgets('the list ends 88 dp clear of it', (tester) async {
      await open(tester, fill: listOfEveryKind);

      final list = tester.widget<ListView>(find.byType(ListView).last);
      expect((list.padding as EdgeInsets).bottom, 88);
    });
  });

  group('at the narrowest and the largest text', () {
    for (final brightness in Brightness.values) {
      testWidgets('360 dp, 200 % text, $brightness, without overflow', (
        tester,
      ) async {
        await open(
          tester,
          size: const Size(360, 800),
          textScale: 2,
          brightness: brightness,
          fill: (s) => s
            ..addOwn(
              'a',
              'quarterly-finance-report-generator',
              private: true,
              people: ['Ana', 'Bob'],
              lastEventAt: todayAt(0, 36),
            )
            ..addOwn('b', 'garage-door', paused: true)
            ..addOwn('c', 'old-sensor', disabledByHost: true)
            ..addVisible('d', 'an-extremely-long-producer-name-that-goes-on')
            ..addVisible('e', 'weather-alerts', owner: 'João', disabled: true),
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(FloatingActionButton), findsOneWidget);
      });
    }

    testWidgets('the states without rows, at 200 %', (tester) async {
      final (app, server) = await open(
        tester,
        size: const Size(360, 800),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);

      server.listFailure = 0;
      await tester.runAsync(app.controller.producers.load);
      await app.settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.textContaining("You're offline"), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'zebra');
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the offline banner and the failed list, at 200 %', (
      tester,
    ) async {
      final (app, server) = await open(
        tester,
        size: const Size(360, 800),
        textScale: 2,
        fill: (s) => s.addVisible('a', 'ana-reports'),
      );
      server.listFailure = 0;
      await tester.runAsync(app.controller.producers.load);
      await app.settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.textContaining("You're offline"), findsOneWidget);
    });
  });

  testWidgets('the bell is named for a screen reader, and the search too', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await open(
      tester,
      fill: (s) => s
        ..addVisible('a', 'ci-pipeline')
        ..addVisible('b', 'price-watch', subscribed: false),
    );

    expect(
      find.bySemanticsLabel(
        'Subscribed to ci-pipeline. Double tap to unsubscribe.',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Not subscribed to price-watch. Double tap to subscribe.',
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('Find a producer')), findsWidgets);
    semantics.dispose();
  });
}
