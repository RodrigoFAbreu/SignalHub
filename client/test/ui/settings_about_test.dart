import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/app_controller.dart';
import 'package:signalhub_client/src/build_identity.dart';
import 'package:signalhub_client/src/onboarding/onboarding_store.dart';
import 'package:signalhub_client/src/ui/about_server_screen.dart';
import 'package:signalhub_client/src/ui/devices_screen.dart';
import 'package:signalhub_client/src/ui/widgets/skeleton.dart';

import '../support/fakes.dart';
import '../support/first_run_support.dart';
import '../support/phone.dart';
import '../support/screenshot.dart';

void main() {
  setUpAll(loadDesignFonts);

  Finder byKey(String key) => find.byKey(Key(key));

  Future<void> shot(WidgetTester tester, String name) =>
      saveScreenshot(tester, byKey('screenshot'), name);

  Future<FirstRunHarness> settings(
    WidgetTester tester, {
    String role = 'BASIC',
    String? devices,
    Size size = const Size(412, 892),
    double textScale = 1,
  }) async {
    final app = FirstRunHarness(role: role, step: OnboardingStep.done);
    FakeServerInfo().install(app.backend);
    useDesignPhone(tester, size: size, textScale: textScale);
    await app.start(tester);
    app.controller.deviceList = FakeDevicesController(app.controller, devices);
    await tester.tap(byKey('tab-settings'));
    await app.settle(tester);
    return app;
  }

  group('Settings', () {
    for (final (role, devices) in [
      ('BASIC', '1 device'),
      ('MOD', '2 devices'),
      ('ADMIN', '4 devices · 1 browser'),
    ]) {
      testWidgets('4b4: has one order for a $role', (tester) async {
        await settings(tester, role: role, devices: devices);

        double top(Finder f) => tester.getTopLeft(f).dy;
        final order = [
          find.text('Push notifications'),
          find.text('Push filters'),
          find.text('Alert'),
          find.text('Devices'),
          find.text('About this server'),
          find.text('This device'),
        ];
        for (final finder in order) {
          expect(finder, findsOneWidget);
        }
        for (var i = 1; i < order.length; i++) {
          expect(top(order[i]), greaterThan(top(order[i - 1])));
        }
        // The summary comes from the Devices feature, whoever asks.
        expect(
          find.descendant(of: byKey('devices'), matching: find.text(devices)),
          findsOneWidget,
        );
        // Signing in a browser is a later change's row.
        expect(find.text('Sign in a browser'), findsNothing);
        await shot(tester, '4b4-$role');
      });
    }

    testWidgets('the Push notifications switch stays at the top', (
      tester,
    ) async {
      await settings(tester);

      expect(byKey('pushEnabled'), findsOneWidget);
      expect(
        tester.getTopLeft(byKey('pushEnabled')).dy,
        lessThan(tester.getTopLeft(byKey('group-pushFilters')).dy),
      );
    });

    testWidgets('the Devices row opens the Devices screen, and the list is '
        'read for it', (tester) async {
      final app = await settings(tester, role: 'ADMIN', devices: '2 devices');
      final devices = app.controller.deviceList as FakeDevicesController;
      expect(devices.loads, greaterThan(0));

      await tester.tap(byKey('devices'));
      await app.settle(tester);

      expect(find.byType(DevicesScreen), findsOneWidget);
    });

    testWidgets('the Devices row has no summary until the devices are read', (
      tester,
    ) async {
      await settings(tester);

      expect(
        find.descendant(of: byKey('devices'), matching: find.byType(Text)),
        findsOneWidget,
      );
    });

    testWidgets('names the server in the About row', (tester) async {
      await settings(tester);

      expect(
        find.descendant(
          of: byKey('aboutServer'),
          matching: find.text('signalhub.test · who can see what'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the groups keep their summaries, with icons', (tester) async {
      await settings(tester);

      expect(find.byKey(const Key('summary-pushFilters')), findsOneWidget);
      expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
      expect(find.byIcon(Icons.phone_android), findsOneWidget);
    });

    testWidgets('fits 360 dp at 200 % text', (tester) async {
      await settings(
        tester,
        role: 'ADMIN',
        devices: '4 devices · 1 browser',
        size: const Size(360, 800),
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        byKey('aboutServer'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(byKey('aboutServer'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('About this server', () {
    Future<(FirstRunHarness, FakeServerInfo)> about(
      WidgetTester tester, {
      String role = 'BASIC',
      FakeServerInfo? info,
      BuildIdentity build = const BuildIdentity(
        version: '3.4.0',
        revision: 'a1b2c3d4e5f60718293a4b5c6d7e8f9012345678',
      ),
    }) async {
      final app = FirstRunHarness(
        role: role,
        step: OnboardingStep.done,
        build: build,
      );
      final server = info ?? FakeServerInfo();
      server.install(app.backend);
      useDesignPhone(tester);
      await app.start(tester);
      await tester.tap(byKey('tab-settings'));
      await app.settle(tester);
      await tester.tap(byKey('aboutServer'));
      await app.settle(tester);
      return (app, server);
    }

    testWidgets('4b5: says where the server is, who you are, both builds and '
        'who can see what', (tester) async {
      await about(tester);

      expect(find.widgetWithText(AppBar, 'About this server'), findsOneWidget);
      expect(find.text('Address'), findsOneWidget);
      expect(find.text(serverUrl), findsOneWidget);
      expect(find.text('You are'), findsOneWidget);
      expect(find.text('Rodrigo · Basic'), findsOneWidget);
      expect(find.text('This app'), findsOneWidget);
      expect(find.text('SignalHub 3.4.0 · commit a1b2c3d'), findsNWidgets(2));
      expect(find.text('Server'), findsOneWidget);
      expect(
        find.text('The host runs this server and can see every event on it.'),
        findsOneWidget,
      );
      await shot(tester, '4b5');
    });

    testWidgets('says the role of the person, whoever they are', (
      tester,
    ) async {
      await about(tester, role: 'ADMIN');

      expect(find.text('Rodrigo · Admin'), findsOneWidget);
    });

    testWidgets('names the server\'s own version and commit', (tester) async {
      await about(
        tester,
        info: FakeServerInfo(version: '3.5.1', commit: '0123456789abcdef'),
      );

      expect(find.text('SignalHub 3.5.1 · commit 0123456'), findsOneWidget);
      expect(find.text('SignalHub 3.4.0 · commit a1b2c3d'), findsOneWidget);
    });

    testWidgets('a development build says so, and a missing commit', (
      tester,
    ) async {
      await about(
        tester,
        info: FakeServerInfo(version: 'development', commit: null),
        build: const BuildIdentity(),
      );

      expect(
        find.text('SignalHub development build · commit unknown'),
        findsNWidgets(2),
      );
    });

    testWidgets('shows a line while the server is read, not a spinner', (
      tester,
    ) async {
      final info = FakeServerInfo()..hold = Completer<void>();
      final app = FirstRunHarness(step: OnboardingStep.done);
      info.install(app.backend);
      useDesignPhone(tester);
      await app.start(tester);
      await tester.tap(byKey('tab-settings'));
      await app.settle(tester);
      await tester.tap(byKey('aboutServer'));
      await tester.pump();
      await tester.runAsync(pumpEventQueue);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(SkeletonRows), findsOneWidget);
      expect(find.text('Server'), findsNothing);

      info.hold!.complete();
      await app.settle(tester);
      expect(find.text('Server'), findsOneWidget);
    });

    testWidgets('a server that has not got it says so', (tester) async {
      await about(tester, info: FakeServerInfo()..missing = true);

      expect(find.text('This server does not say'), findsOneWidget);
      expect(byKey('retryServer'), findsNothing);
    });

    testWidgets('a server in trouble can be asked again', (tester) async {
      final (app, info) = await about(
        tester,
        info: FakeServerInfo()..fails = true,
      );
      expect(find.text("Couldn't read it from the server"), findsOneWidget);

      info.fails = false;
      await tester.tap(byKey('retryServer'));
      await app.settle(tester);

      expect(find.text('SignalHub 3.4.0 · commit a1b2c3d'), findsNWidgets(2));
      expect(byKey('retryServer'), findsNothing);
    });

    testWidgets('a revoked key ends it quietly at setup', (tester) async {
      final app = FirstRunHarness(step: OnboardingStep.done);
      FakeServerInfo().install(app.backend);
      useDesignPhone(tester);
      await app.start(tester);
      await tester.tap(byKey('tab-settings'));
      await app.settle(tester);
      app.backend.acceptedKey = null;

      await tester.tap(byKey('aboutServer'));
      await app.settle(tester);

      expect(app.controller.phase, ConnectionPhase.disconnected);
      expect(find.byType(AboutServerScreen), findsNothing);
      expect(find.textContaining('no longer connected'), findsOneWidget);
    });

    testWidgets('fits 360 dp at 200 % text with a long address', (
      tester,
    ) async {
      final app = FirstRunHarness(step: OnboardingStep.done);
      FakeServerInfo().install(app.backend);
      useDesignPhone(tester, size: const Size(360, 800), textScale: 2);
      await app.start(tester);
      await tester.tap(byKey('tab-settings'));
      await app.settle(tester);
      await tester.tap(byKey('aboutServer'));
      await app.settle(tester);

      expect(tester.takeException(), isNull);
    });
  });
}
