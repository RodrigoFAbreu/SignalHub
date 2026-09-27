import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/app_controller.dart';
import 'package:signalhub_client/src/connection/pairing_uri.dart';
import 'package:signalhub_client/src/ui/connect_device_screen.dart';

import '../support/fakes.dart';
import '../support/phone.dart';

void main() {
  final created = DateTime.utc(2026, 9, 27, 12);
  late FakeBackend backend;
  late AppController controller;
  late DateTime now;

  setUp(() {
    now = created;
    backend = FakeBackend()
      ..admin = true
      ..pairingExpiresAt = created.add(const Duration(minutes: 10));
    controller = AppController(
      store: InMemoryCredentialsStore(),
      apiFactory: (credentials) =>
          backend.api(credentials.baseUrl, credentials.clientKey),
      redeemPairing: backend.redeemPairing,
    );
  });

  Future<void> show(WidgetTester tester) async {
    await tester.runAsync(() => controller.connect(serverUrl, clientKey));
    await tester.pumpWidget(
      MaterialApp(
        home: ConnectDeviceScreen(controller: controller, now: () => now),
      ),
    );
  }

  Future<void> create(WidgetTester tester, String name) async {
    await tester.enterText(find.byKey(const Key('pairingName')), name);
    await tester.tap(find.byKey(const Key('createPairing')));
    await tester.runAsync(pumpEventQueue);
    await tester.pump();
  }

  /// Lets the screen ask once whether the code was used, and shows the
  /// answer.
  Future<void> poll(WidgetTester tester) async {
    await tester.pump(ConnectDeviceScreen.pollInterval);
    await tester.runAsync(pumpEventQueue);
    await tester.pump();
  }

  String countdown(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('countdown'))).data!;

  testWidgets('shows the code as a QR code with its countdown and link', (
    tester,
  ) async {
    await show(tester);

    await create(tester, 'Tablet');

    expect(backend.devicePairingNames, ['Tablet']);
    expect(find.text('Pairing code for "Tablet"'), findsOneWidget);
    final link = controller.pairingLink!;
    expect(PairingUri.parse(link).code, controller.pairing!.code);
    expect(tester.widget<PairingQr>(find.byType(PairingQr)).data, link);
    expect(find.text(link), findsOneWidget);
    expect(countdown(tester), 'Expires in 10:00. It works once.');

    now = created.add(const Duration(seconds: 61));
    await tester.pump(const Duration(seconds: 1));
    expect(countdown(tester), 'Expires in 8:59. It works once.');

    now = created.add(const Duration(minutes: 10));
    await tester.pump(const Duration(seconds: 1));
    expect(countdown(tester), 'This code has expired.');
    expect(find.byType(PairingQr), findsNothing);
    expect(find.byKey(const Key('copyLink')), findsNothing);
    expect(find.text(link), findsNothing);

    await tester.tap(find.byKey(const Key('newPairing')));
    await tester.pump();
    expect(controller.pairing, isNull);
    expect(find.byKey(const Key('createPairing')), findsOneWidget);
  });

  testWidgets('the code scrolls clear of the navigation bar', (tester) async {
    useEdgeToEdgePhone(tester);
    // Larger text, as set in the phone's accessibility settings, makes the
    // code longer than the screen.
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await show(tester);
    await create(tester, 'Tablet');

    await scrollToEnd(tester, find.byType(ConnectDeviceScreen));

    expectClearOfNavigationBar(tester, find.byKey(const Key('newPairing')));
  });

  testWidgets('copies the pairing link', (tester) async {
    final copied = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') copied.add(call.arguments);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await show(tester);
    await create(tester, 'Tablet');

    await tester.tap(find.byKey(const Key('copyLink')));
    await tester.pump();

    expect(copied, [
      {'text': controller.pairingLink},
    ]);
    expect(find.text('Pairing link copied.'), findsOneWidget);
  });

  testWidgets('a server without a public address still gets a link', (
    tester,
  ) async {
    backend.publicUrl = null;
    await show(tester);

    await create(tester, 'Tablet');

    final link = tester.widget<PairingQr>(find.byType(PairingQr)).data;
    expect(PairingUri.parse(link).serverUrl, serverUrl);
    expect(find.text(link), findsOneWidget);
  });

  testWidgets('a blank name is not sent', (tester) async {
    await show(tester);

    await create(tester, '   ');

    expect(find.text('Enter a name of up to 100 characters'), findsOneWidget);
    expect(backend.devicePairingNames, isEmpty);
    expect(controller.pairing, isNull);
  });

  group('a used code', () {
    testWidgets('names the device and is ready for the next one', (
      tester,
    ) async {
      await show(tester);
      await create(tester, 'Tablet');
      await poll(tester);
      expect(find.byType(PairingQr), findsOneWidget);

      backend.usePairing('Anna\'s tablet');
      await poll(tester);

      expect(
        find.text('"Anna\'s tablet" connected with the pairing code.'),
        findsOneWidget,
      );
      expect(find.byType(PairingQr), findsNothing);
      expect(find.byKey(const Key('pairingLink')), findsNothing);
      expect(controller.pairing, isNull);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('pairingName')))
            .controller!
            .text,
        isEmpty,
      );
      final requests = backend.pairingStatusRequests;
      await poll(tester);
      expect(backend.pairingStatusRequests, requests);

      await create(tester, 'Laptop');
      expect(find.text('Pairing code for "Laptop"'), findsOneWidget);
    });

    testWidgets('is asked about only while the screen is shown', (
      tester,
    ) async {
      await show(tester);
      await create(tester, 'Tablet');
      await poll(tester);
      expect(backend.pairingStatusRequests, 1);

      await tester.pumpWidget(const SizedBox());
      await poll(tester);
      await poll(tester);

      expect(backend.pairingStatusRequests, 1);
    });

    testWidgets('is not asked about while the app is in the background', (
      tester,
    ) async {
      void move(List<AppLifecycleState> states) {
        for (final state in states) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
      }

      await show(tester);
      await create(tester, 'Tablet');

      move([AppLifecycleState.inactive, AppLifecycleState.hidden]);
      await poll(tester);
      move([AppLifecycleState.paused]);
      await poll(tester);
      expect(backend.pairingStatusRequests, 0);

      move([
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]);
      await poll(tester);
      expect(backend.pairingStatusRequests, 1);
    });

    testWidgets('is asked about once more as it expires, then no more', (
      tester,
    ) async {
      await show(tester);
      await create(tester, 'Tablet');

      now = created.add(const Duration(minutes: 10));
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(pumpEventQueue);
      expect(backend.pairingStatusRequests, 1);
      await poll(tester);
      await poll(tester);

      expect(backend.pairingStatusRequests, 1);
      expect(countdown(tester), 'This code has expired.');
    });

    testWidgets('used in its last seconds is still announced', (tester) async {
      await show(tester);
      await create(tester, 'Tablet');
      backend.usePairing('Tablet');

      now = created.add(const Duration(minutes: 10));
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(pumpEventQueue);
      await tester.pump();

      expect(
        find.text('"Tablet" connected with the pairing code.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('createPairing')), findsOneWidget);
    });

    testWidgets('by a device that lost its admin rights says so', (
      tester,
    ) async {
      await show(tester);
      await create(tester, 'Tablet');
      backend.admin = false;

      await poll(tester);

      expect(find.text(AppController.notAdminMessage), findsOneWidget);
      expect(find.byType(PairingQr), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('createPairing')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('an older server leaves the screen as it was', (tester) async {
      backend.pairingIds = false;
      await show(tester);
      await create(tester, 'Tablet');

      await poll(tester);

      expect(backend.pairingStatusRequests, 0);
      expect(find.byType(PairingQr), findsOneWidget);
      expect(find.byKey(const Key('pairingError')), findsNothing);
    });

    for (final status in [404, 405]) {
      testWidgets('a server answering $status leaves the screen as it was', (
        tester,
      ) async {
        backend.noPairingStatus = status;
        await show(tester);
        await create(tester, 'Tablet');

        await poll(tester);
        await poll(tester);

        expect(backend.pairingStatusRequests, 1);
        expect(find.byType(PairingQr), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
        expect(find.byKey(const Key('pairingError')), findsNothing);
      });
    }
  });
}
