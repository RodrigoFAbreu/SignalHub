import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';
import '../support/own_producers_fake.dart';
import '../support/phone.dart';
import '../support/producer_screens.dart';

/// Who can answer a producer's questions, on the owner's screen, and the line
/// that asks an unsubscribed owner or answerer to stay subscribed.
void main() {
  const ana = {'id': 'u-ana', 'name': 'Ana'};

  Finder byKey(String key) => find.byKey(Key(key));

  Future<(AppHarness, OwnProducersFake)> setup(WidgetTester tester) async {
    final app = AppHarness(role: 'MOD');
    useDesignPhone(tester, size: const Size(412, 1400));
    final fake = OwnProducersFake(app.backend)
      ..addPerson('u-ana', 'Ana')
      ..addPerson('u-rui', 'Rui');
    return (app, fake);
  }

  testWidgets('the owner is listed first, with no control', (tester) async {
    final (app, fake) = await setup(tester);
    fake.own('p-1', 'homelab-monitor');
    await app.start(tester);
    await openProducer(tester, app, 'p-1');

    expect(find.text('Who can answer'), findsOneWidget);
    expect(find.text('Rodrigo (you)'), findsOneWidget);
    expect(find.text('Owner · can always answer'), findsOneWidget);
    expect(
      find.text("Only you can answer this producer's questions."),
      findsOneWidget,
    );
    expect(byKey('addAnswerers'), findsOneWidget);
    expect(find.byTooltip('Remove Rodrigo from Who can answer'), findsNothing);
  });

  testWidgets('each added person has a close button named for them', (
    tester,
  ) async {
    final (app, fake) = await setup(tester);
    fake.own('p-1', 'homelab-monitor', answerers: [ana]);
    await app.start(tester);
    await openProducer(tester, app, 'p-1');

    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('Can answer its questions'), findsOneWidget);
    expect(find.byTooltip('Remove Ana from Who can answer'), findsOneWidget);
    expect(
      find.text("Only you can answer this producer's questions."),
      findsNothing,
    );
  });

  testWidgets('removing asks first, and changes only that person', (
    tester,
  ) async {
    final (app, fake) = await setup(tester);
    fake.own('p-1', 'homelab-monitor', answerers: [ana]);
    await app.start(tester);
    await openProducer(tester, app, 'p-1');

    await tester.tap(find.byTooltip('Remove Ana from Who can answer'));
    await app.settle(tester);
    expect(find.text('Remove Ana?'), findsOneWidget);
    expect(
      find.text(
        "Ana won't be able to answer homelab-monitor's questions any more. "
        'Answers Ana already gave stay as they are.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await app.settle(tester);
    expect(fake.calls.where((c) => c.contains('answerers')), isEmpty);

    await tester.tap(find.byTooltip('Remove Ana from Who can answer'));
    await app.settle(tester);
    await tester.tap(byKey('confirm'));
    await app.settle(tester);

    expect(
      fake.calls,
      contains('DELETE /api/v1/client/producers/p-1/answerers/u-ana'),
    );
    expect(find.text('Can answer its questions'), findsNothing);
    expect(
      find.text("Only you can answer this producer's questions."),
      findsOneWidget,
    );
  });

  testWidgets('a removal that fails says Not removed, with Retry', (
    tester,
  ) async {
    final (app, fake) = await setup(tester);
    fake.own('p-1', 'homelab-monitor', answerers: [ana]);
    await app.start(tester);
    await openProducer(tester, app, 'p-1');
    fake.failures['DELETE /api/v1/client/producers/p-1/answerers/u-ana'] = 500;

    await tester.tap(find.byTooltip('Remove Ana from Who can answer'));
    await app.settle(tester);
    await tester.tap(byKey('confirm'));
    await app.settle(tester);
    expect(find.text('Not removed'), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await app.settle(tester);
    // Retry asks again before it removes.
    await tester.tap(byKey('confirm'));
    await app.settle(tester);
    expect(find.text('Can answer its questions'), findsNothing);
  });

  group('the picker', () {
    testWidgets('lists who can see it and cannot answer yet, none checked', (
      tester,
    ) async {
      final (app, fake) = await setup(tester);
      fake.own(
        'p-1',
        'homelab-monitor',
        allowed: [
          ana,
          {'id': 'u-rui', 'name': 'Rui'},
        ],
        answerers: [ana],
      );
      await app.start(tester);
      await openProducer(tester, app, 'p-1');

      await tester.tap(byKey('addAnswerers'));
      await app.settle(tester);

      expect(find.text('Add people who can answer'), findsOneWidget);
      expect(byKey('candidate-u-rui'), findsOneWidget);
      expect(byKey('candidate-u-ana'), findsNothing);
      expect(
        find.text(
          'Only people who can see homelab-monitor are listed. They also need '
          'to be subscribed to get its questions.',
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<CheckboxListTile>(byKey('candidate-u-rui')).value,
        isFalse,
      );
      // Add is off until someone is checked.
      expect(
        tester.widget<FilledButton>(byKey('addAnswerers').last).onPressed,
        isNull,
      );
    });

    testWidgets('adds the people checked, and nothing else', (tester) async {
      final (app, fake) = await setup(tester);
      fake.own('p-1', 'homelab-monitor', allowed: [ana]);
      await app.start(tester);
      await openProducer(tester, app, 'p-1');

      await tester.tap(byKey('addAnswerers'));
      await app.settle(tester);
      await tester.tap(byKey('candidate-u-ana'));
      await app.settle(tester);
      await tester.tap(byKey('addAnswerers').last);
      await app.settle(tester);

      expect(
        fake.calls,
        contains('PUT /api/v1/client/producers/p-1/answerers/u-ana'),
      );
      expect(find.text('Can answer its questions'), findsOneWidget);
    });

    testWidgets('a public producer offers everyone', (tester) async {
      final (app, fake) = await setup(tester);
      fake.own('p-1', 'homelab-monitor', visibility: 'PUBLIC');
      await app.start(tester);
      await openProducer(tester, app, 'p-1');

      await tester.tap(byKey('addAnswerers'));
      await app.settle(tester);

      expect(byKey('candidate-u-ana'), findsOneWidget);
      expect(byKey('candidate-u-rui'), findsOneWidget);
    });

    testWidgets('with everyone already answering, it says so', (tester) async {
      final (app, fake) = await setup(tester);
      fake.own('p-1', 'homelab-monitor', allowed: [ana], answerers: [ana]);
      await app.start(tester);
      await openProducer(tester, app, 'p-1');

      await tester.tap(byKey('addAnswerers'));
      await app.settle(tester);

      expect(
        find.text('Everyone who can see homelab-monitor can already answer.'),
        findsOneWidget,
      );
    });

    testWidgets('with nobody else able to see it, it says so', (tester) async {
      final (app, fake) = await setup(tester);
      fake.own('p-1', 'homelab-monitor');
      await app.start(tester);
      await openProducer(tester, app, 'p-1');

      await tester.tap(byKey('addAnswerers'));
      await app.settle(tester);

      expect(
        find.text(
          'Nobody else can see homelab-monitor. Add people under Who can see '
          'it first.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('leaving with someone checked asks to discard', (tester) async {
      final (app, fake) = await setup(tester);
      fake.own('p-1', 'homelab-monitor', allowed: [ana]);
      await app.start(tester);
      await openProducer(tester, app, 'p-1');

      await tester.tap(byKey('addAnswerers'));
      await app.settle(tester);
      await tester.tap(byKey('candidate-u-ana'));
      await tester.tap(find.byTooltip('Close'));
      await app.settle(tester);

      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(byKey('confirm'));
      await app.settle(tester);
      expect(find.byTooltip('Close'), findsNothing);
      expect(fake.calls.where((c) => c.contains('answerers')), isEmpty);
    });
  });

  group('Stay subscribed to answer', () {
    testWidgets('is said to an owner who unsubscribed', (tester) async {
      final (app, fake) = await setup(tester);
      fake.own('p-1', 'homelab-monitor', subscribed: false);
      await app.start(tester);
      await openProducer(tester, app, 'p-1');

      expect(find.text('Stay subscribed to answer'), findsOneWidget);
      expect(
        find.text(
          "While you're unsubscribed, homelab-monitor's questions don't "
          "reach you, and you can't answer them.",
        ),
        findsOneWidget,
      );
    });

    testWidgets('is not said while subscribed', (tester) async {
      final (app, fake) = await setup(tester);
      fake.own('p-1', 'homelab-monitor');
      await app.start(tester);
      await openProducer(tester, app, 'p-1');

      expect(find.text('Stay subscribed to answer'), findsNothing);
    });

    testWidgets('is said to an answerer of somebody else\'s producer', (
      tester,
    ) async {
      final (app, fake) = await setup(tester);
      fake.other('p-2', 'ci-pipeline', 'Ana', canAnswer: true);
      await app.start(tester);
      await openProducer(tester, app, 'p-2');

      expect(find.text('Stay subscribed to answer'), findsOneWidget);
    });

    testWidgets('is not said to someone who cannot answer', (tester) async {
      final (app, fake) = await setup(tester);
      fake.other('p-2', 'ci-pipeline', 'Ana');
      await app.start(tester);
      await openProducer(tester, app, 'p-2');

      expect(find.text('Stay subscribed to answer'), findsNothing);
    });
  });
}
