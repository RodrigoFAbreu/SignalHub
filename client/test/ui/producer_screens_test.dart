import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/app_controller.dart';
import 'package:signalhub_client/src/ui/allow_list_screen.dart';
import 'package:signalhub_client/src/ui/new_producer_screen.dart';
import 'package:signalhub_client/src/ui/producer_key_screen.dart';
import 'package:signalhub_client/src/ui/producer_screen.dart';
import 'package:signalhub_client/src/models/producers.dart';
import 'package:signalhub_client/src/models/users.dart';
import 'package:signalhub_client/src/ui/widgets/copy_button.dart';

import '../support/harness.dart';
import '../support/own_producers_fake.dart';
import '../support/phone.dart';
import '../support/producer_screens.dart';

void main() {
  const ana = {'id': 'u-ana', 'name': 'Ana'};
  const marta = {'id': 'u-marta', 'name': 'Marta'};

  Future<(AppHarness, OwnProducersFake, FakePlatform)> setup(
    WidgetTester tester, {
    String role = 'MOD',
    Size size = const Size(412, 1200),
    double textScale = 1,
  }) async {
    final app = AppHarness(role: role);
    useDesignPhone(tester, size: size, textScale: textScale);
    final fake = OwnProducersFake(app.backend)
      ..addPerson('u-ana', 'Ana')
      ..addPerson('u-marta', 'Marta');
    return (app, fake, FakePlatform(tester));
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('producerName')), text);
    await tester.pump();
  }

  bool createOn(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(const Key('create'))).onPressed !=
      null;

  for (final role in ['BASIC', 'MOD', 'ADMIN']) {
    group('as $role', () {
      testWidgets('creates a producer and shows its key once', (tester) async {
        final (app, fake, platform) = await setup(tester, role: role);
        await app.start(tester);
        await pushScreen(
          tester,
          app,
          NewProducerScreen(controller: app.controller),
        );
        expect(createOn(tester), isFalse);

        await type(tester, 'garage-door');
        expect(createOn(tester), isTrue);
        await tester.tap(find.byKey(const Key('create')));
        await app.settle(tester);

        expect(find.text('garage-door is ready'), findsOneWidget);
        expect(fake.owned.single['visibility'], 'PRIVATE');
        final key = (fake.owned.single['keys'] as List).single as Map;
        expect(find.textContaining('shpk1_${key['id']}_secret'), findsWidgets);
        // Copy and close copies the key and leaves for the producer.
        await tester.tap(find.byKey(const Key('copyAndClose')));
        await app.settle(tester);
        expect(platform.copied.single, startsWith('shpk1_NEW'));
        expect(find.byType(ProducerScreen), findsOneWidget);
        expect(find.text('shpk1_NEW1…'), findsOneWidget);
      });

      testWidgets('subscribes to or leaves someone else\'s producer', (
        tester,
      ) async {
        final (app, fake, _) = await setup(tester, role: role);
        fake.other('p-3', 'weather-alerts', 'João');
        await app.start(tester);
        await openProducer(tester, app, 'p-3');

        expect(find.text("João's producer"), findsOneWidget);
        expect(find.text('See its events'), findsNothing);
        expect(find.text('Rename weather-alerts'), findsNothing);
        await tester.tap(find.byType(Switch));
        await app.settle(tester);

        expect(fake.others.single['subscribed'], isTrue);
        expect(find.text('See its events'), findsOneWidget);
        expect(
          snack(
            'Subscribed to weather-alerts. Its older events are in your inbox too.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Undo'));
        await app.settle(tester);
        expect(fake.others.single['subscribed'], isFalse);
      });
    });
  }

  group('names', () {
    testWidgets('are checked while typed, and Create waits', (tester) async {
      final (app, fake, _) = await setup(tester);
      fake.hiddenNames.add('ci-pipeline');
      await app.start(tester);
      await pushScreen(
        tester,
        app,
        NewProducerScreen(controller: app.controller),
      );

      await type(tester, 'garage door');
      expect(
        find.text(
          'Use letters, numbers and . _ : / - only, starting with a letter or number.',
        ),
        findsOneWidget,
      );
      expect(createOn(tester), isFalse);
      await type(tester, 'a' * 101);
      expect(find.text('Use 100 characters or fewer.'), findsOneWidget);
      await type(tester, '');
      expect(find.text('Give it a name.'), findsNothing);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(find.text('Give it a name.'), findsOneWidget);

      await type(tester, 'ci-pipeline');
      await tester.tap(find.byKey(const Key('create')));
      await app.settle(tester);
      expect(find.textContaining('That name is taken'), findsOneWidget);
      expect(createOn(tester), isFalse);
      expect(find.byKey(const Key('openMine')), findsNothing);
      await type(tester, 'ci-pipeline2');
      expect(createOn(tester), isTrue);
    });

    testWidgets('a lost answer says the producer is already yours', (
      tester,
    ) async {
      final (app, fake, _) = await setup(tester);
      fake.loseNextCreate = true;
      await app.start(tester);
      await pushScreen(
        tester,
        app,
        NewProducerScreen(controller: app.controller),
      );
      await type(tester, 'garage-door');
      await tester.tap(find.byKey(const Key('create')));
      await app.settle(tester);
      expect(
        find.textContaining("Couldn't create garage-door"),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('create')));
      await app.settle(tester);

      expect(
        find.text('You already have a producer called garage-door.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Your first try probably worked'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('openMine')));
      await app.settle(tester);
      expect(find.byType(ProducerScreen), findsOneWidget);
      expect(find.text('Make a new key to start.'), findsNothing);
    });

    testWidgets('rename shows the same errors and is off until valid', (
      tester,
    ) async {
      final (app, fake, _) = await setup(tester);
      fake.own('p-1', 'homelab-monitor');
      fake.hiddenNames.add('taken-one');
      await app.start(tester);
      await openProducer(tester, app, 'p-1');

      await tester.tap(find.byTooltip('Rename homelab-monitor'));
      await app.settle(tester);
      TextButton rename() =>
          tester.widget<TextButton>(find.byKey(const Key('rename')));
      expect(rename().onPressed, isNull);
      await type(tester, 'taken-one');
      await tester.tap(find.byKey(const Key('rename')));
      await app.settle(tester);
      expect(find.textContaining('That name is taken'), findsOneWidget);
      await type(tester, 'homelab-nas');
      await tester.tap(find.byKey(const Key('rename')));
      await app.settle(tester);

      expect(find.text('homelab-nas'), findsOneWidget);
      expect(fake.owned.single['name'], 'homelab-nas');
    });
  });

  group('the key screen', () {
    testWidgets('asks once on leaving, only if the key was not kept', (
      tester,
    ) async {
      final (app, _, platform) = await setup(tester);
      await app.start(tester);
      await pushScreen(
        tester,
        app,
        ProducerKeyScreen(
          controller: app.controller,
          issued: sampleIssuedKey(),
          isNew: false,
        ),
      );
      expect(find.byTooltip('Close'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await app.settle(tester);
      expect(find.text('Did you copy the key?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('stay')));
      await app.settle(tester);
      expect(find.byType(ProducerKeyScreen), findsOneWidget);

      // System Back goes through the same guard.
      await tester.binding.handlePopRoute();
      await app.settle(tester);
      expect(find.text('Did you copy the key?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('stay')));
      await app.settle(tester);

      await tester.tap(find.byType(CopyButton));
      await app.settle(tester);
      expect(platform.copied, [sampleKey]);
      expect(find.text('Copied'), findsWidgets);
      expect(find.text('Done'), findsOneWidget);
      // Copied stays while the screen is open.
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Done'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await app.settle(tester);
      expect(find.byType(ProducerKeyScreen), findsNothing);
    });

    testWidgets('sharing counts as keeping the key', (tester) async {
      final (app, _, platform) = await setup(tester);
      await app.start(tester);
      await pushScreen(
        tester,
        app,
        ProducerKeyScreen(
          controller: app.controller,
          issued: sampleIssuedKey(),
          isNew: false,
        ),
      );
      await tester.tap(find.text('Share'));
      await app.settle(tester);
      expect(platform.shared, [sampleKey]);
      await tester.tap(find.byTooltip('Close'));
      await app.settle(tester);
      expect(find.text('Did you copy the key?'), findsNothing);
      expect(find.byType(ProducerKeyScreen), findsNothing);
    });

    testWidgets('a refused clipboard selects the key and says how', (
      tester,
    ) async {
      final (app, _, platform) = await setup(tester);
      platform.refuseClipboard = true;
      await app.start(tester);
      await pushScreen(
        tester,
        app,
        ProducerKeyScreen(
          controller: app.controller,
          issued: sampleIssuedKey(),
        ),
      );

      await tester.tap(find.byKey(const Key('copyAndClose')));
      await app.settle(tester);

      expect(find.byKey(const Key('copyByHand')), findsOneWidget);
      expect(find.byType(ProducerKeyScreen), findsOneWidget);
      final key = tester.widget<TextField>(find.byKey(const Key('apiKey')));
      expect(key.controller!.selection.isCollapsed, isFalse);
    });

    testWidgets('only the sample key is in the send example', (tester) async {
      final (app, _, _) = await setup(tester);
      await app.start(tester);
      await pushScreen(
        tester,
        app,
        ProducerKeyScreen(
          controller: app.controller,
          issued: IssuedProducerKey(
            producer: sampleIssuedKey().producer,
            keyId: 'K',
            apiKey: 'shpk1_REAL-secret-0000',
          ),
        ),
      );
      expect(find.text('shpk1_REAL-secret-0000'), findsOneWidget);
      expect(find.textContaining('shpk1_REAL'), findsOneWidget);
      expect(find.textContaining('signalhub.example'), findsOneWidget);
      expect(
        find.textContaining('shpk1_EXAMPLEKEY-not-a-real-key-0000'),
        findsOneWidget,
      );
    });

    testWidgets('fits 360 dp at 200 % text', (tester) async {
      final (app, _, _) = await setup(
        tester,
        size: const Size(360, 900),
        textScale: 2,
      );
      await app.start(tester);
      await pushScreen(
        tester,
        app,
        ProducerKeyScreen(
          controller: app.controller,
          issued: sampleIssuedKey(),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Copy and close'), findsOneWidget);
    });
  });

  group('your producer', () {
    testWidgets('keys, revoke asks, and the only key says so', (tester) async {
      final (app, fake, _) = await setup(tester);
      fake.own(
        'p-1',
        'backup-jobs',
        keys: [OwnProducersFake.key('EXAMPLE1', prefix: 'shpk1_EXAMPLE1')],
      );
      await app.start(tester);
      final semantics = tester.ensureSemantics();
      await tester.pump();
      await openProducer(tester, app, 'p-1');

      expect(find.text('shpk1_EXAMPLE1…'), findsOneWidget);
      expect(find.textContaining('not used yet'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Revoke key shpk1_EXAMPLE1…')),
        findsOneWidget,
      );
      expect(find.byTooltip('Rename backup-jobs'), findsWidgets);
      await tester.tap(find.text('Revoke'));
      await app.settle(tester);
      expect(find.text('Revoke the only key?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await app.settle(tester);
      expect(
        ((fake.owned.single['keys'] as List).single as Map)['revokedAt'],
        isNull,
      );

      await tester.tap(find.text('Revoke'));
      await app.settle(tester);
      await tester.tap(find.byKey(const Key('confirm')));
      await app.settle(tester);
      expect(find.textContaining('No working key.'), findsOneWidget);
      expect(find.textContaining('Revoked '), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('a new key opens the key screen again', (tester) async {
      final (app, fake, _) = await setup(tester);
      fake.own('p-1', 'garage-door');
      await app.start(tester);
      await openProducer(tester, app, 'p-1');

      await tester.tap(find.byKey(const Key('newKey')));
      await app.settle(tester);

      expect(find.text('New key for garage-door'), findsOneWidget);
      expect(find.textContaining('This is its new key'), findsOneWidget);
      await tester.tap(find.byType(CopyButton));
      await app.settle(tester);
      await tester.tap(find.text('Done'));
      await app.settle(tester);
      expect(find.byType(ProducerScreen), findsOneWidget);
      expect(find.text('shpk1_NEW1…'), findsOneWidget);
    });

    testWidgets('visibility asks only when going private', (tester) async {
      final (app, fake, _) = await setup(tester);
      fake.own('p-1', 'ci-pipeline', visibility: 'PUBLIC');
      await app.start(tester);
      await openProducer(tester, app, 'p-1');
      expect(
        find.text('Anyone on this server can find and subscribe to it.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Private'));
      await app.settle(tester);
      expect(find.text('Make ci-pipeline private?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await app.settle(tester);
      expect(fake.owned.single['visibility'], 'PUBLIC');

      await tester.tap(find.text('Private'));
      await app.settle(tester);
      await tester.tap(find.byKey(const Key('confirm')));
      await app.settle(tester);
      expect(fake.owned.single['visibility'], 'PRIVATE');
      expect(find.text('Only you'), findsOneWidget);

      await tester.tap(find.text('Public'));
      await app.settle(tester);
      expect(fake.owned.single['visibility'], 'PUBLIC');
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('the sharing line and chips, removing asks first', (
      tester,
    ) async {
      final (app, fake, _) = await setup(tester);
      fake.own('p-1', 'homelab-monitor', allowed: [ana, marta]);
      await app.start(tester);
      final semantics = tester.ensureSemantics();
      await tester.pump();
      await openProducer(tester, app, 'p-1');
      await tester.pump();
      expect(find.text('Shared with 2 people'), findsOneWidget);
      expect(find.byTooltip('Remove Marta'), findsWidgets);

      await tester.tap(find.byTooltip('Remove Marta'));
      await app.settle(tester);
      expect(find.text('Remove Marta?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm')));
      await app.settle(tester);

      expect(find.text('Shared with 1 person'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('disable asks, enable does not', (tester) async {
      final (app, fake, _) = await setup(tester);
      fake.own('p-1', 'garage-door');
      await app.start(tester);
      await openProducer(tester, app, 'p-1');

      await tester.tap(find.byKey(const Key('disable')));
      await app.settle(tester);
      expect(find.text('Disable garage-door?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm')));
      await app.settle(tester);
      expect(find.textContaining('Disabled by you.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('enable')));
      await app.settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(fake.owned.single['disabledAt'], isNull);
    });

    testWidgets('disabled by the host: Enable is off and sends nothing', (
      tester,
    ) async {
      final (app, fake, _) = await setup(tester);
      fake.own(
        'p-1',
        'old-sensor',
        disabledAt: '2026-10-01T09:00:00Z',
        disabledByOperator: true,
      );
      await app.start(tester);
      await openProducer(tester, app, 'p-1');
      expect(find.textContaining('Disabled by the host.'), findsOneWidget);
      expect(find.text('Only the host can enable it'), findsOneWidget);
      fake.calls.clear();

      await tester.tap(find.byKey(const Key('enable')));
      await app.settle(tester);

      expect(fake.calls.where((c) => c.contains('enable')), isEmpty);
    });

    testWidgets('a failed change says nothing changed, with Retry', (
      tester,
    ) async {
      final (app, fake, _) = await setup(tester);
      fake.own('p-1', 'garage-door');
      await app.start(tester);
      await openProducer(tester, app, 'p-1');
      fake.failures['POST /api/v1/client/producers/p-1/disable'] = 500;

      await tester.tap(find.byKey(const Key('disable')));
      await app.settle(tester);
      await tester.tap(find.byKey(const Key('confirm')));
      await app.settle(tester);

      expect(
        snack('SignalHub had a problem. Try again in a moment.'),
        findsOneWidget,
      );
      expect(fake.owned.single['disabledAt'], isNull);
      await tester.tap(find.text('Retry'));
      await app.settle(tester);
      expect(fake.owned.single['disabledAt'], isNotNull);
    });

    testWidgets('a producer gone meanwhile ends on its own screen', (
      tester,
    ) async {
      final (app, fake, _) = await setup(tester);
      fake.own('p-1', 'garage-door');
      await app.start(tester);
      await openProducer(tester, app, 'p-1');
      fake.owned.clear();

      await tester.tap(find.byKey(const Key('disable')));
      await app.settle(tester);
      await tester.tap(find.byKey(const Key('confirm')));
      await app.settle(tester);

      expect(
        find.text("This producer isn't available\nany more"),
        findsOneWidget,
      );
      await tester.tap(find.text('Back to Producers'));
      await app.settle(tester);
      expect(app.controller.tab, HomeTab.producers);
      expect(find.byType(ProducerScreen), findsNothing);
    });

    testWidgets('a key no longer accepted ends quietly', (tester) async {
      final (app, fake, _) = await setup(tester);
      fake.own('p-1', 'garage-door');
      await app.start(tester);
      await openProducer(tester, app, 'p-1');
      app.backend.acceptedKey = null;

      await tester.tap(find.byKey(const Key('disable')));
      await app.settle(tester);
      await tester.tap(find.byKey(const Key('confirm')));
      await app.settle(tester);

      expect(app.controller.phase, ConnectionPhase.disconnected);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a role that no longer allows it is read again', (
      tester,
    ) async {
      final (app, fake, _) = await setup(tester);
      fake.own('p-1', 'garage-door');
      await app.start(tester);
      await openProducer(tester, app, 'p-1');
      app.backend.userRole = 'BASIC';
      fake.failures['POST /api/v1/client/producers/p-1/disable'] = 403;

      await tester.tap(find.byKey(const Key('disable')));
      await app.settle(tester);
      await tester.tap(find.byKey(const Key('confirm')));
      await app.settle(tester);

      expect(app.controller.role, UserRole.basic);
      expect(
        snack("Your role doesn't allow this. It may have changed."),
        findsOneWidget,
      );
    });

    testWidgets('offline: an older state under a banner, writes paused', (
      tester,
    ) async {
      final (app, fake, _) = await setup(tester);
      fake.own('p-1', 'garage-door');
      await app.start(tester);
      await app.controller.ownProducers.load();
      app.backend.offline = true;
      await openProducer(tester, app, 'p-1');

      expect(find.textContaining("You're offline."), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.edit_outlined),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('the first read failing says so, with Try again', (
      tester,
    ) async {
      final (app, fake, _) = await setup(tester);
      fake.own('p-1', 'garage-door');
      await app.start(tester);
      app.backend.offline = true;
      await openProducer(tester, app, 'p-1');
      expect(find.text("Couldn't load this producer"), findsOneWidget);

      app.backend.offline = false;
      await tester.tap(find.text('Try again'));
      await app.settle(tester);
      expect(find.text('garage-door'), findsWidgets);
    });

    testWidgets('fits 360 dp at 200 % text', (tester) async {
      final (app, fake, _) = await setup(
        tester,
        size: const Size(360, 900),
        textScale: 2,
      );
      fake.own(
        'p-1',
        'a-rather-long-producer-name-that-goes-on-and-on',
        allowed: [ana, marta],
        disabledAt: '2026-10-01T09:00:00Z',
        keys: [
          OwnProducersFake.key('EXAMPLE1', prefix: 'shpk1_EXAMPLE1'),
          OwnProducersFake.key('EXAMPLE2', prefix: 'shpk1_EXAMPLE2'),
        ],
      );
      await app.start(tester);
      await openProducer(tester, app, 'p-1');
      expect(tester.takeException(), isNull);
    });

    testWidgets('light theme builds without overflow', (tester) async {
      final (app, fake, _) = await setup(tester);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      fake.own('p-1', 'garage-door', allowed: [ana]);
      await app.start(tester);
      await openProducer(tester, app, 'p-1');
      expect(tester.takeException(), isNull);
    });
  });

  group('someone else\'s producer', () {
    testWidgets('private one shared with you, muted here, opens filters', (
      tester,
    ) async {
      final (app, fake, _) = await setup(tester);
      fake.other(
        'p-3',
        'family-calendar',
        'Ana',
        visibility: 'PRIVATE',
        subscribed: true,
      );
      app.backend.pushPreferences = {
        ...app.backend.pushPreferences!,
        'mutedProducerIds': ['p-3'],
      };
      await app.start(tester);
      await openProducer(tester, app, 'p-3');

      expect(find.text('Ana added you'), findsOneWidget);
      expect(find.text('Muted on this device'), findsOneWidget);
      await tester.tap(find.text('Muted on this device'));
      await app.settle(tester);

      expect(app.controller.tab, HomeTab.settings);
      expect(
        app.controller.openSettingsGroups.map((g) => g.name),
        contains('pushFilters'),
      );
      expect(find.byType(ProducerScreen), findsNothing);
    });

    testWidgets('a producer made private since is not available', (
      tester,
    ) async {
      final (app, _, _) = await setup(tester);
      await app.start(tester);
      await openProducer(tester, app, 'p-gone');
      expect(find.text('Producer'), findsOneWidget);
      expect(
        find.textContaining('It may have been made private.'),
        findsOneWidget,
      );
    });

    testWidgets('a failed subscribe goes back and offers Retry', (
      tester,
    ) async {
      final (app, fake, _) = await setup(tester);
      fake.other('p-3', 'weather-alerts', 'João');
      await app.start(tester);
      await openProducer(tester, app, 'p-3');
      fake.failures['PUT /api/v1/client/visible-producers/p-3/subscription'] =
          500;

      await tester.tap(find.byType(Switch));
      await app.settle(tester);

      expect(
        snack("Couldn't subscribe to weather-alerts. Try again."),
        findsOneWidget,
      );
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    });

    testWidgets('your own producer you left shows the owner sentence', (
      tester,
    ) async {
      final (app, fake, _) = await setup(tester);
      fake.own('p-1', 'ci-pipeline', visibility: 'PUBLIC', subscribed: false);
      await app.start(tester);
      await openProducer(tester, app, 'p-1');
      expect(
        find.text(
          "You own it but don't get its events. Anyone on this server can still subscribe.",
        ),
        findsOneWidget,
      );
      expect(find.text('See its events'), findsNothing);
    });
  });

  group('adding people', () {
    Future<void> open(
      WidgetTester tester,
      AppHarness app,
      OwnProducersFake fake,
    ) async {
      await app.start(tester);
      await app.controller.ownProducers.load();
      await pushScreen(
        tester,
        app,
        AllowListScreen(
          controller: app.controller,
          producer: OwnProducer.fromJson(fake.owned.single),
        ),
      );
    }

    testWidgets('names only, Save off until the selection changes', (
      tester,
    ) async {
      final (app, fake, _) = await setup(tester);
      fake.own('p-1', 'homelab-monitor');
      await open(tester, app, fake);
      expect(find.text('Ana'), findsOneWidget);
      expect(find.text('Rodrigo'), findsNothing);
      FilledButton save() =>
          tester.widget<FilledButton>(find.byKey(const Key('saveAllowList')));
      expect(save().onPressed, isNull);

      await tester.tap(find.text('Ana'));
      await tester.pump();
      expect(save().onPressed, isNotNull);
      await tester.tap(find.text('Ana'));
      await tester.pump();
      expect(save().onPressed, isNull);

      await tester.tap(find.text('Marta'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('saveAllowList')));
      await app.settle(tester);
      // Adding alone saves straight away.
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        ((fake.owned.single['allowedUsers'] as List).single as Map)['name'],
        'Marta',
      );
    });

    testWidgets('removing someone asks, and a failed save keeps the screen', (
      tester,
    ) async {
      final (app, fake, _) = await setup(tester);
      fake.own('p-1', 'homelab-monitor', allowed: [ana, marta]);
      await open(tester, app, fake);
      await tester.tap(find.text('Marta'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('saveAllowList')));
      await app.settle(tester);
      expect(find.text('Save these changes?'), findsOneWidget);
      fake.failures['DELETE /api/v1/client/producers/p-1/allowed-users/u-marta'] =
          500;
      await tester.tap(find.byKey(const Key('confirm')));
      await app.settle(tester);

      expect(
        snack("Couldn't save. Your changes are still here."),
        findsOneWidget,
      );
      expect(find.byType(AllowListScreen), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await app.settle(tester);
      expect(find.byType(AllowListScreen), findsNothing);
      expect(
        ((fake.owned.single['allowedUsers'] as List).single as Map)['name'],
        'Ana',
      );
    });

    testWidgets('nobody else on the server', (tester) async {
      final app = AppHarness(role: 'MOD');
      useDesignPhone(tester);
      final fake = OwnProducersFake(app.backend)..own('p-1', 'garage-door');
      await open(tester, app, fake);
      expect(find.text('Nobody else is here yet'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('saveAllowList')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('many people get a search, with a count', (tester) async {
      final (app, fake, _) = await setup(tester);
      for (var i = 0; i < 9; i++) {
        fake.addPerson('u-$i', 'Person$i');
      }
      fake.own('p-1', 'homelab-monitor', allowed: [ana]);
      await open(tester, app, fake);
      final semantics = tester.ensureSemantics();
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Person3');
      await tester.pump();
      expect(find.byKey(const Key('person-u-3')), findsOneWidget);
      expect(find.byKey(const Key('person-u-4')), findsNothing);
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byTooltip('Clear search'), findsOneWidget);
      semantics.dispose();
    });
  });
}
