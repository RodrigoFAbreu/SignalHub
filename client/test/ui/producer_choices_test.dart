import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/onboarding/onboarding_store.dart';
import 'package:signalhub_client/src/ui/pairing_scanner_screen.dart';

import '../support/first_run_support.dart';
import '../support/phone.dart';

void main() {
  Finder byKey(String key) => find.byKey(Key(key));

  Future<(FirstRunHarness, FakeVisibleProducers)> inbox(
    WidgetTester tester, {
    Size size = const Size(412, 892),
    double textScale = 1,
  }) async {
    final app = FirstRunHarness(step: OnboardingStep.done);
    app.backend
      ..publish('e-1', 'Build failed')
      ..publish(
        'e-2',
        'Disk full',
        producer: {'id': 'p-2', 'name': 'nas-monitor'},
      );
    final producers = FakeVisibleProducers()
      ..add('p-3', 'zeta-jobs')
      ..add('p-1', 'nightly-build')
      ..add('p-2', 'nas-monitor')
      ..add('p-9', 'not-subscribed', subscribed: false)
      ..install(app.backend);
    useDesignPhone(tester, size: size, textScale: textScale);
    await app.start(tester);
    return (app, producers);
  }

  group('the inbox filter', () {
    testWidgets('offers the producers this user subscribes to, A to Z', (
      tester,
    ) async {
      final (app, producers) = await inbox(tester);
      final reads = producers.reads;

      await tester.tap(find.byTooltip('Filter events'));
      await app.settle(tester);

      // Opening it reads the list again.
      expect(producers.reads, greaterThan(reads));
      final chips = find.byWidgetPredicate(
        (w) =>
            w is FilterChip &&
            (w.key as ValueKey?)?.value.toString().startsWith(
                  'filterProducer-',
                ) ==
                true,
      );
      expect(
        [
          for (final chip in tester.widgetList<FilterChip>(chips))
            ((chip.label as Text).data),
        ],
        ['nas-monitor', 'nightly-build', 'zeta-jobs'],
      );
      expect(find.text('not-subscribed'), findsNothing);
    });

    testWidgets('says what fills it when nothing is subscribed', (
      tester,
    ) async {
      final (app, producers) = await inbox(tester);
      for (final p in producers.producers) {
        p['subscribed'] = false;
      }

      await tester.tap(find.byTooltip('Filter events'));
      await app.settle(tester);

      expect(
        find.text('Producers you subscribe to appear here.'),
        findsOneWidget,
      );
    });

    testWidgets('keeps a producer the filter names after it is unsubscribed '
        'from, so the filter can be taken off', (tester) async {
      final (app, producers) = await inbox(tester);
      await tester.tap(find.byTooltip('Filter events'));
      await app.settle(tester);
      await tester.tap(byKey('filterProducer-p-2'));
      await app.settle(tester);
      await tester.tapAt(const Offset(10, 10));
      await app.settle(tester);

      // Unsubscribed meanwhile: the list no longer has it as subscribed.
      producers.producers.firstWhere((p) => p['id'] == 'p-2')['subscribed'] =
          false;
      await tester.tap(find.byTooltip('Filter events'));
      await app.settle(tester);

      final chip = tester.widget<FilterChip>(byKey('filterProducer-p-2'));
      expect(chip.selected, isTrue);
      expect((chip.label as Text).data, 'nas-monitor');
      await tester.tap(byKey('filterProducer-p-2'));
      await app.settle(tester);
      expect(app.controller.filter.producerIds, isEmpty);
    });

    testWidgets('the bar names the filtered producer, by its ID when it is '
        'unknown', (tester) async {
      final (app, _) = await inbox(tester);

      await tester.runAsync(
        () => app.controller.setFilter(
          app.controller.filter.copyWith(producerIds: {'p-1', 'p-unknown'}),
        ),
      );
      await app.settle(tester);

      final bar = find.byKey(const Key('activeFilters'));
      expect(
        find.descendant(of: bar, matching: find.text('nightly-build')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: bar, matching: find.text('p-unknown')),
        findsOneWidget,
      );
    });
  });

  group('push filters', () {
    Future<void> openPushFilters(
      WidgetTester tester,
      FirstRunHarness app,
    ) async {
      tester.view
        ..physicalSize = const Size(800, 4000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.tap(byKey('tab-settings'));
      await app.settle(tester);
      await tester.tap(byKey('summary-pushFilters'));
      await app.settle(tester);
    }

    testWidgets('list the producers this user subscribes to', (tester) async {
      final (app, _) = await inbox(tester);

      await openPushFilters(tester, app);

      expect(byKey('producer-p-1'), findsOneWidget);
      expect(byKey('producer-p-2'), findsOneWidget);
      expect(byKey('producer-p-3'), findsOneWidget);
      expect(byKey('producer-p-9'), findsNothing);
    });

    testWidgets('keep a muted producer that is not listed, by name when it '
        'is known and by ID when it is not', (tester) async {
      final (app, _) = await inbox(tester);
      app.backend.pushPreferences = {
        'enabled': true,
        'minimumSeverity': 'LOW',
        'mutedCategories': <String>[],
        'mutedProducerIds': ['p-9', 'p-gone'],
      };
      await tester.runAsync(app.controller.refresh);

      await openPushFilters(tester, app);

      // p-9 is visible to this user but not subscribed to.
      expect(
        find.descendant(of: byKey('producer-p-9'), matching: find.text('p-9')),
        findsNothing,
      );
      expect(find.text('not-subscribed'), findsOneWidget);
      expect(find.text('p-gone'), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(byKey('producer-p-gone')).value,
        isFalse,
      );

      await tester.tap(byKey('producer-p-gone'));
      await app.settle(tester);
      expect(app.backend.pushPreferences?['mutedProducerIds'], ['p-9']);
    });
  });

  testWidgets('the inbox fits 360 dp at 200 % text with banners and long '
      'names', (tester) async {
    final app = FirstRunHarness(role: 'ADMIN');
    app.backend.publish(
      'e-1',
      'A very long event title that has to wrap over more than one line of '
          'the inbox',
      producer: {
        'id': 'p-7',
        'name': 'a-producer-with-a-really-long-name-that-cannot-fit',
      },
    );
    useDesignPhone(tester, size: const Size(360, 800), textScale: 2);
    await app.start(tester);
    app.backend.offline = true;
    await tester.runAsync(app.controller.refresh);
    await app.settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text("What's new"), findsOneWidget);
    expect(find.textContaining("You're offline."), findsOneWidget);
  });

  testWidgets('the camera region is named for what to point at', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PairingScannerView(
            handlers: PairingScanHandlers(
              onCode: (_) {},
              onCameraUnavailable: () {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.bySemanticsLabel('Camera, point at the invitation code'),
      findsOneWidget,
    );
    semantics.dispose();
  });
}
