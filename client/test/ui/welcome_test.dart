import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/app_controller.dart';
import 'package:signalhub_client/src/onboarding/onboarding_store.dart';

import '../support/fakes.dart';
import '../support/first_run_support.dart';
import '../support/phone.dart';
import '../support/screenshot.dart';

void main() {
  setUpAll(loadDesignFonts);

  Finder byKey(String key) => find.byKey(Key(key));

  Future<void> shot(WidgetTester tester, String name) =>
      saveScreenshot(tester, byKey('screenshot'), name);

  /// A device that just paired with a code, as a person with [role] and
  /// [name].
  Future<FirstRunHarness> pair(
    WidgetTester tester, {
    String role = 'BASIC',
    String name = 'Rui',
    Size size = const Size(412, 892),
    double textScale = 1,
  }) async {
    final app = FirstRunHarness(role: role);
    app.backend
      ..userName = name
      ..pairingCodes.add(pairingCode);
    useDesignPhone(tester, size: size, textScale: textScale);
    await app.start(tester, connected: false);
    app.camera.scan(pairingUri);
    await app.settle(tester);
    return app;
  }

  group('the welcome', () {
    testWidgets('4b: says who and where the device is, to a Basic user', (
      tester,
    ) async {
      await pair(tester);

      expect(find.text('Welcome, Rui'), findsOneWidget);
      expect(
        find.text("You're connected to signalhub.test as Pixel 8."),
        findsOneWidget,
      );
      expect(
        find.textContaining('Producers send events', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Your inbox holds their events',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Your own producers: make one', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.text('The host runs this server and can see every event on it.'),
        findsOneWidget,
      );
      // A Basic user's welcome has no People, Devices or browser line.
      expect(find.textContaining('People:', findRichText: true), findsNothing);
      expect(
        find.textContaining('Devices in Settings', findRichText: true),
        findsNothing,
      );
      // Before the bar appears.
      expect(find.byKey(const Key('tab-inbox')), findsNothing);
      await shot(tester, '4b');
    });

    testWidgets('4b2: an admin\'s adds People, Devices and signing in a '
        'browser', (tester) async {
      await pair(tester, role: 'ADMIN', name: 'Sofia');

      expect(find.text('Welcome, Sofia'), findsOneWidget);
      expect(
        find.text(
          "You're connected to signalhub.test as Pixel 8, an admin device.",
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'People: invite people, set them to Basic or Mod, '
          'and manage their devices.',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Devices in Settings connects your other phones.',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Sign in a browser puts SignalHub on a computer.',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Producers send events. Subscribe to the ones you '
          'want, or make your own.',
          findRichText: true,
        ),
        findsOneWidget,
      );
      await shot(tester, '4b2');
    });

    testWidgets('4b2: a Mod\'s omits People', (tester) async {
      await pair(tester, role: 'MOD', name: 'Ana');

      expect(find.text('Welcome, Ana'), findsOneWidget);
      expect(
        find.text("You're connected to signalhub.test as Pixel 8."),
        findsOneWidget,
      );
      expect(find.textContaining('People:', findRichText: true), findsNothing);
      expect(
        find.textContaining(
          'Devices in Settings connects your other phones.',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Sign in a browser', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('asked', findRichText: true), findsNothing);
    });

    testWidgets('Later opens the inbox, and the welcome is said once', (
      tester,
    ) async {
      final app = await pair(tester);
      app.backend.publish('e-1', 'Build failed');

      await tester.tap(byKey('welcomeLater'));
      await app.settle(tester);

      expect(find.text('Welcome, Rui'), findsNothing);
      expect(byKey('tab-inbox'), findsOneWidget);
      expect(app.controller.tab, HomeTab.inbox);
      expect(app.onboardingStore.saved, OnboardingStep.done);
      // No What's new for a device that got the welcome.
      expect(byKey('whatsNew'), findsNothing);
    });

    testWidgets('Find producers opens the Producers tab', (tester) async {
      final app = await pair(tester);

      await tester.tap(byKey('welcomeFindProducers'));
      await app.settle(tester);

      expect(app.controller.tab, HomeTab.producers);
      expect(find.widgetWithText(AppBar, 'Producers'), findsOneWidget);
      expect(app.onboardingStore.saved, OnboardingStep.done);
    });

    testWidgets('a device that connects with a client key gets it too', (
      tester,
    ) async {
      final app = FirstRunHarness();
      useDesignPhone(tester);
      await app.start(tester, connected: false);
      app.backend.acceptedKey = clientKey;

      await tester.tap(byKey('byHand'));
      await tester.pumpAndSettle();
      await tester.enterText(byKey('serverUrl'), serverUrl);
      await tester.enterText(byKey('clientKey'), clientKey);
      await tester.tap(byKey('connect'));
      await app.settle(tester);

      expect(find.text('Welcome, Rodrigo'), findsOneWidget);
      expect(app.onboardingStore.saved, OnboardingStep.welcome);
    });

    testWidgets('one not dismissed comes back after a restart', (tester) async {
      final app = FirstRunHarness(step: OnboardingStep.welcome);
      useDesignPhone(tester);

      await app.start(tester);

      expect(find.text('Welcome, Rodrigo'), findsOneWidget);
    });

    testWidgets('is not said again to a device that has had it', (
      tester,
    ) async {
      final app = FirstRunHarness(step: OnboardingStep.done);
      useDesignPhone(tester);

      await app.start(tester);

      expect(find.textContaining('Welcome'), findsNothing);
      expect(byKey('whatsNew'), findsNothing);
      expect(byKey('tab-inbox'), findsOneWidget);
    });

    testWidgets('fits 360 dp at 200 % text, and scrolls', (tester) async {
      await pair(
        tester,
        role: 'ADMIN',
        name: 'Sofia',
        size: const Size(360, 640),
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
      expect(byKey('welcomeFindProducers'), findsOneWidget);
      await tester.ensureVisible(
        find.textContaining('The host runs this server'),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a store that fails still lets the device in', (tester) async {
      final app = FirstRunHarness();
      app.onboardingStore.fails = true;
      app.backend.pairingCodes.add(pairingCode);
      useDesignPhone(tester);
      await app.start(tester, connected: false);

      app.camera.scan(pairingUri);
      await app.settle(tester);

      // The welcome is said, and ending it works without the store.
      expect(find.text('Welcome, Rodrigo'), findsOneWidget);
      await tester.tap(byKey('welcomeLater'));
      await app.settle(tester);
      expect(byKey('tab-inbox'), findsOneWidget);
    });

    testWidgets('a controller without a store says nothing', (tester) async {
      final backend = FakeBackend()..pairingCodes.add(pairingCode);
      final controller = AppController(
        store: InMemoryCredentialsStore(),
        apiFactory: (c) => backend.api(c.baseUrl, c.clientKey),
        redeemPairing: backend.redeemPairing,
      );

      expect(await controller.pair(pairingUri), isNull);

      expect(controller.onboarding, OnboardingStep.done);
    });
  });

  group('what\'s new', () {
    Future<FirstRunHarness> upgraded(
      WidgetTester tester, {
      String role = 'ADMIN',
    }) async {
      // No record: the device was connected before the app kept one.
      final app = FirstRunHarness(role: role);
      app.backend
        ..publish('e-2', 'Disk at 80%', category: 'ACTION_REQUIRED')
        ..publish(
          'e-1',
          'Backup finished',
          category: 'INFO',
          severity: 'NORMAL',
        );
      useDesignPhone(tester);
      await app.start(tester);
      return app;
    }

    testWidgets('4b3: is a card at the top of the inbox of a device that was '
        'connected already', (tester) async {
      await upgraded(tester);

      expect(find.text("What's new"), findsOneWidget);
      expect(
        find.textContaining(
          'A bottom bar. Inbox, Producers and Settings are '
          'one tap away.',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Producers. Make your own, share them, and '
          "subscribe to others'.",
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'People. Invite people and manage their devices.',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(find.text('See Producers'), findsOneWidget);
      expect(find.text('Got it'), findsOneWidget);
      // Above the events.
      expect(
        tester.getTopLeft(byKey('whatsNew')).dy,
        lessThan(tester.getTopLeft(find.text('Disk at 80%')).dy),
      );
      await shot(tester, '4b3');
    });

    for (final role in ['BASIC', 'MOD']) {
      testWidgets('has no People line for a $role', (tester) async {
        await upgraded(tester, role: role);

        expect(find.text("What's new"), findsOneWidget);
        expect(
          find.textContaining('People.', findRichText: true),
          findsNothing,
        );
      });
    }

    testWidgets('Got it dismisses it for good', (tester) async {
      final app = await upgraded(tester);

      await tester.tap(byKey('whatsNewGotIt'));
      await app.settle(tester);

      expect(find.text("What's new"), findsNothing);
      expect(app.controller.tab, HomeTab.inbox);
      expect(app.onboardingStore.saved, OnboardingStep.done);
    });

    testWidgets('See Producers opens the tab and dismisses', (tester) async {
      final app = await upgraded(tester);

      await tester.tap(byKey('whatsNewSeeProducers'));
      await app.settle(tester);

      expect(app.controller.tab, HomeTab.producers);
      expect(app.onboardingStore.saved, OnboardingStep.done);
      await app.openTabInbox(tester);
      expect(find.text("What's new"), findsNothing);
    });

    testWidgets('does not come back after a restart', (tester) async {
      final app = await upgraded(tester);
      await tester.tap(byKey('whatsNewGotIt'));
      await app.settle(tester);

      final again = FirstRunHarness(step: app.onboardingStore.saved);
      useDesignPhone(tester);
      await again.start(tester);

      expect(find.text("What's new"), findsNothing);
    });

    testWidgets('comes back after a restart until it is dismissed', (
      tester,
    ) async {
      final first = await upgraded(tester);
      expect(first.onboardingStore.saved, isNull);

      final again = FirstRunHarness(role: 'ADMIN');
      useDesignPhone(tester);
      await again.start(tester);

      expect(find.text("What's new"), findsOneWidget);
    });

    testWidgets('fits 360 dp at 200 % text', (tester) async {
      final app = FirstRunHarness(role: 'ADMIN');
      app.backend.publish('e-1', 'Backup finished');
      useDesignPhone(tester, size: const Size(360, 800), textScale: 2);

      await app.start(tester);

      expect(tester.takeException(), isNull);
      expect(find.text("What's new"), findsOneWidget);
    });
  });
}

extension on FirstRunHarness {
  Future<void> openTabInbox(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('tab-inbox')));
    await settle(tester);
  }
}
