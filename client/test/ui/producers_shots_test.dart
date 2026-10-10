// Draws the Producers frames of the design for comparing with the drawings:
// run with SIGNALHUB_SCREENSHOTS=<dir>. Without it they only check that the
// frames build.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/app_controller.dart';

import 'package:signalhub_client/src/ui/producer_events_screen.dart';

import '../support/harness.dart';
import '../support/phone.dart';
import '../support/producers_backend.dart';
import '../support/screenshot.dart';

void main() {
  setUpAll(loadDesignFonts);

  Future<void> shot(WidgetTester tester, String name) =>
      saveScreenshot(tester, find.byKey(screenshotKey), name);

  AppHarness harness({int unread = 3}) {
    final app = AppHarness();
    for (var i = 0; i < unread; i++) {
      app.backend.publish('e$i', 'Event $i');
    }
    return app;
  }

  FakeProducers listOf1d(AppHarness app) => FakeProducers(app.backend)
    ..addOwn('p1', 'backup-jobs', private: true, lastEventAt: todayAt(0, 41))
    ..addOwn('p2', 'ci-pipeline', keys: 2, lastEventAt: todayAt(1, 19))
    ..addOwn(
      'p3',
      'homelab-monitor',
      private: true,
      people: ['Ana', 'Bob'],
      lastEventAt: todayAt(0, 36),
    )
    ..addOwn('p4', 'quarterly-finance-report-generator', private: true)
    ..addVisible('p5', 'ana-reports')
    ..addVisible('p6', 'family-calendar', private: true)
    ..addVisible('p7', 'price-watch', owner: 'João', subscribed: false)
    ..addVisible('p8', 'weather-alerts', owner: 'João', subscribed: false);

  FakeProducers fewRows(AppHarness app) => FakeProducers(app.backend)
    ..addOwn('p2', 'ci-pipeline', keys: 2, lastEventAt: todayAt(1, 19))
    ..addVisible('p5', 'ana-reports')
    ..addVisible('p7', 'price-watch', owner: 'João', subscribed: false)
    ..addVisible('p8', 'weather-alerts', owner: 'João', subscribed: false);

  for (final brightness in [Brightness.dark, Brightness.light]) {
    final suffix = brightness == Brightness.dark ? '' : '-light';

    testWidgets('1d $brightness', (tester) async {
      final app = harness();
      listOf1d(app);
      useDesignPhone(tester, brightness: brightness);
      await app.start(tester);
      await app.openTab(tester, HomeTab.producers);
      await shot(tester, '1d$suffix');
    });

    testWidgets('1g $brightness', (tester) async {
      final app = harness();
      app.backend.pushPreferences = {
        ...?app.backend.pushPreferences,
        'mutedProducerIds': ['p5'],
      };
      FakeProducers(app.backend)
        ..addOwn('p2', 'ci-pipeline', keys: 2, lastEventAt: todayAt(1, 19))
        ..addOwn('p9', 'garage-door', paused: true)
        ..addOwn('p10', 'old-sensor', disabledByHost: true)
        ..addVisible('p5', 'ana-reports')
        ..addVisible('p6', 'family-calendar', private: true)
        ..addVisible('p8', 'weather-alerts', owner: 'João', disabled: true)
        ..addVisible('p7', 'price-watch', owner: 'João', subscribed: false);
      useDesignPhone(tester, brightness: brightness);
      await app.start(tester);
      await app.openTab(tester, HomeTab.producers);
      await shot(tester, '1g$suffix');
    });
  }

  testWidgets('1f', (tester) async {
    final app = harness();
    listOf1d(app);
    useDesignPhone(tester);
    await app.start(tester);
    await app.openTab(tester, HomeTab.producers);
    await tester.enterText(find.byType(TextField), 'zebra');
    await app.settle(tester);
    await shot(tester, '1f');
  });

  testWidgets('1h and 4j2 in flight', (tester) async {
    final app = harness();
    final producers = fewRows(app);
    useDesignPhone(tester);
    final semantics = tester.ensureSemantics();
    await app.start(tester);
    await app.openTab(tester, HomeTab.producers);
    producers.holdSubscriptions = Completer();
    await tester.tap(find.bySemanticsLabel(RegExp('Not subscribed to price')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await shot(tester, '1h');
    producers.holdSubscriptions!.complete();
    await app.settle(tester);
    semantics.dispose();
  });

  testWidgets('1i failed', (tester) async {
    final app = harness();
    final producers = fewRows(app);
    producers.subscribeFailures['p7'] = 500;
    useDesignPhone(tester);
    final semantics = tester.ensureSemantics();
    await app.start(tester);
    await app.openTab(tester, HomeTab.producers);
    await tester.tap(find.bySemanticsLabel(RegExp('Not subscribed to price')));
    await app.settle(tester);
    await shot(tester, '1i');
    semantics.dispose();
  });

  testWidgets('5g failed, light', (tester) async {
    final app = harness();
    final producers = fewRows(app);
    producers.subscribeFailures['p7'] = 500;
    useDesignPhone(tester, brightness: Brightness.light);
    final semantics = tester.ensureSemantics();
    await app.start(tester);
    await app.openTab(tester, HomeTab.producers);
    await tester.tap(find.bySemanticsLabel(RegExp('Not subscribed to price')));
    await app.settle(tester);
    await shot(tester, '5g');
    semantics.dispose();
  });

  testWidgets('1j undo', (tester) async {
    final app = harness(unread: 2);
    fewRows(app);
    useDesignPhone(tester);
    final semantics = tester.ensureSemantics();
    await app.start(tester);
    await app.openTab(tester, HomeTab.producers);
    await tester.tap(
      find.bySemanticsLabel(RegExp('Subscribed to ana-reports')),
    );
    await app.settle(tester);
    await shot(tester, '1j');
    semantics.dispose();
  });

  testWidgets('1n 360 wide 200 percent', (tester) async {
    final app = harness();
    FakeProducers(app.backend)
      ..addOwn('p4', 'quarterly-finance-report-generator', private: true)
      ..addOwn('p2', 'ci-pipeline', keys: 2, lastEventAt: todayAt(1, 19))
      ..addVisible('p5', 'ana-reports');
    useDesignPhone(tester, size: const Size(360, 820), textScale: 2);
    await app.start(tester);
    await app.openTab(tester, HomeTab.producers);
    await shot(tester, '1n');
  });

  testWidgets('4d none', (tester) async {
    final app = harness(unread: 0);
    FakeProducers(app.backend);
    useDesignPhone(tester);
    await app.start(tester);
    await app.openTab(tester, HomeTab.producers);
    await shot(tester, '4d');
  });

  testWidgets('4g nothing under Yours', (tester) async {
    final app = harness(unread: 0);
    FakeProducers(app.backend).addVisible('p5', 'ana-reports');
    useDesignPhone(tester);
    await app.start(tester);
    await app.openTab(tester, HomeTab.producers);
    await tester.tap(find.byKey(const Key('producerFilter-yours')));
    await app.settle(tester);
    await shot(tester, '4g');
  });

  testWidgets('4h nothing under Can subscribe', (tester) async {
    final app = harness(unread: 0);
    FakeProducers(app.backend).addVisible('p5', 'ana-reports');
    useDesignPhone(tester);
    await app.start(tester);
    await app.openTab(tester, HomeTab.producers);
    await tester.tap(find.byKey(const Key('producerFilter-canSubscribe')));
    await app.settle(tester);
    await shot(tester, '4h');
  });

  testWidgets('4i list that did not load', (tester) async {
    final app = harness(unread: 0);
    FakeProducers(app.backend).listFailure = 0;
    useDesignPhone(tester);
    await app.start(tester);
    await app.openTab(tester, HomeTab.producers);
    await shot(tester, '4i');
  });

  for (final brightness in [Brightness.dark, Brightness.light]) {
    testWidgets('4j offline $brightness', (tester) async {
      final app = harness();
      final producers = FakeProducers(app.backend)
        ..addVisible('p5', 'ana-reports', subscribed: false)
        ..addOwn('p6', 'homelab-monitor', keys: 2, lastEventAt: todayAt(18, 9))
        ..addVisible('p7', 'ci-pipeline', owner: 'Ana', private: true);
      useDesignPhone(tester, brightness: brightness);
      await app.start(tester);
      await app.openTab(tester, HomeTab.producers);
      producers.listFailure = 0;
      await tester.runAsync(app.controller.producers.load);
      await app.settle(tester);
      await shot(tester, brightness == Brightness.dark ? '4j' : '5h');
    });
  }

  testWidgets('4j2 in flight and one that failed', (tester) async {
    final app = harness();
    final producers = FakeProducers(app.backend)
      ..addVisible('p5', 'ana-reports', subscribed: false)
      ..addVisible('p7', 'ci-pipeline', owner: 'João', private: true);
    producers.subscribeFailures['p7'] = 500;
    useDesignPhone(tester);
    final semantics = tester.ensureSemantics();
    await app.start(tester);
    await app.openTab(tester, HomeTab.producers);
    await tester.tap(
      find.bySemanticsLabel(RegExp('Subscribed to ci-pipeline')),
    );
    await app.settle(tester);
    producers.holdSubscriptions = Completer();
    await tester.tap(find.bySemanticsLabel(RegExp('Not subscribed to ana')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await shot(tester, '4j2');
    producers.holdSubscriptions!.complete();
    await app.settle(tester);
    semantics.dispose();
  });

  testWidgets('4l loading', (tester) async {
    final app = harness(unread: 0);
    final producers = FakeProducers(app.backend)..holdLists = Completer();
    useDesignPhone(tester);
    await app.start(tester);
    await tester.tap(find.byKey(const Key('tab-producers')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await shot(tester, '4l');
    producers.holdLists!.complete();
    await app.settle(tester);
  });

  testWidgets('1l events of a producer', (tester) async {
    final app = harness(unread: 0);
    const ci = {'id': 'p2', 'name': 'ci-pipeline'};
    app.backend
      ..publish(
        'e3',
        'Build 412 passed',
        category: 'INFO',
        severity: 'NORMAL',
        readAt: '2026-09-25T12:10:00Z',
        producer: ci,
      )
      ..publish(
        'e2',
        'Deploy to staging done',
        category: 'COMPLETED',
        severity: 'LOW',
        readAt: '2026-09-25T12:10:00Z',
        producer: ci,
      )
      ..publish(
        'e1',
        'Your action: approve the release',
        category: 'ACTION_REQUIRED',
        severity: 'HIGH',
        producer: ci,
      );
    useDesignPhone(tester);
    await app.start(tester);
    final context = tester.element(find.byType(Scaffold).first);
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProducerEventsScreen(
            controller: app.controller,
            producerId: 'p2',
            producerName: 'ci-pipeline',
          ),
        ),
      ),
    );
    await app.settle(tester);
    await shot(tester, '1l');
  });

  testWidgets('1m no events from it yet', (tester) async {
    final app = harness(unread: 0);
    useDesignPhone(tester);
    await app.start(tester);
    final context = tester.element(find.byType(Scaffold).first);
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProducerEventsScreen(
            controller: app.controller,
            producerId: 'p9',
            producerName: 'garage-door',
          ),
        ),
      ),
    );
    await app.settle(tester);
    await shot(tester, '1m');
  });

  for (final (name, count, tab, role) in [
    ('1k-0', 3, HomeTab.inbox, 'BASIC'),
    ('1k-1', 42, HomeTab.inbox, 'BASIC'),
    ('1k-2', 99, HomeTab.producers, 'BASIC'),
    ('1k-3', 101, HomeTab.settings, 'ADMIN'),
  ]) {
    testWidgets('$name bar and badge', (tester) async {
      final app = AppHarness(role: role);
      for (var i = 0; i < count; i++) {
        app.backend.publish('e$i', 'Event $i');
      }
      FakeProducers(app.backend);
      useDesignPhone(tester);
      await app.start(tester);
      if (tab != HomeTab.inbox) await app.openTab(tester, tab);
      await shot(tester, name);
    });
  }
}
