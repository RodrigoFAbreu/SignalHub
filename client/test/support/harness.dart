import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/app.dart';
import 'package:signalhub_client/src/app_controller.dart';
import 'package:signalhub_client/src/connection/server_credentials.dart';

import 'fakes.dart';
import 'screenshot.dart';

/// The app against an in-memory server, for the tests of one screen: a
/// connected device of the role under test. Add what the server holds to
/// [backend] (and its `handlers`) before [start].
///
/// ```dart
/// final app = AppHarness(role: 'MOD');
/// testWidgets('...', (tester) async {
///   await app.start(tester);
///   ...
/// });
/// ```
class AppHarness {
  /// [role] is `BASIC`, `MOD` or `ADMIN`: what the device's user may do.
  AppHarness({String role = 'BASIC'}) {
    backend
      ..userRole = role
      ..admin = role == 'ADMIN';
    controller = AppController(
      store: store,
      apiFactory: (credentials) =>
          backend.api(credentials.baseUrl, credentials.clientKey),
      redeemPairing: backend.redeemPairing,
      push: push,
    );
  }

  final backend = FakeBackend();
  final push = FakePushService();
  final store = InMemoryCredentialsStore();
  late final AppController controller;

  /// The links the app handed to the platform.
  final openedLinks = <Uri>[];

  /// Opens the app on a device that is already set up, and lets the first
  /// reads finish. Pass [connected] `false` to stop at setup.
  Future<void> start(WidgetTester tester, {bool connected = true}) async {
    if (connected) {
      store.saved = ServerCredentials.parse(serverUrl, clientKey);
    }
    await tester.pumpWidget(
      RepaintBoundary(
        key: screenshotKey,
        child: SignalHubApp(
          controller: controller,
          linkOpener: (link) async {
            openedLinks.add(link);
            return true;
          },
        ),
      ),
    );
    await tester.runAsync(controller.start);
    await settle(tester);
  }

  /// Lets requests answer and animations finish.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
  }

  /// Taps a tab of the bottom bar.
  Future<void> openTab(WidgetTester tester, HomeTab tab) async {
    await tester.tap(find.byKey(Key('tab-${tab.name}')));
    await settle(tester);
  }
}
