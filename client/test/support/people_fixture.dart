import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/app_controller.dart';

import 'fake_platform.dart';
import 'harness.dart';
import 'people_backend.dart';
import 'phone.dart';

/// A device of one role on a server with the design's people, for the tests of
/// the people and devices screens, with a clock the test moves and the
/// platform's share sheet, clipboard and announcements recorded.
///
/// The caller is Rodrigo (an admin), Ana (a mod) or João (a basic user), as
/// the design's frames draw them.
class PeopleFixture {
  PeopleFixture(String role)
    : app = AppHarness(role: role),
      now = DateTime.utc(2026, 10, 10, 12) {
    final backend = app.backend
      ..userName = switch (role) {
        'ADMIN' => 'Rodrigo',
        'MOD' => 'Ana',
        _ => 'João',
      };
    people = PeopleBackend(backend);
    app.controller.clock = () => now;
    people.pairingExpiresAt = now.add(const Duration(minutes: 10));
    if (role == 'ADMIN') {
      people.seedDesignData(now);
    } else {
      people.seedOwnDevices(now);
    }
  }

  final AppHarness app;
  late final PeopleBackend people;
  late final FakePlatform platform;

  /// What the screens read as the time; move it with [advance].
  DateTime now;

  AppController get controller => app.controller;

  /// Opens the app, on the phone of the design's frames.
  Future<void> start(
    WidgetTester tester, {
    Size size = const Size(412, 892),
    double textScale = 1,
    Brightness brightness = Brightness.dark,
  }) async {
    platform = FakePlatform(tester);
    useDesignPhone(
      tester,
      size: size,
      textScale: textScale,
      brightness: brightness,
    );
    await app.start(tester);
  }

  /// Opens Settings > Devices.
  Future<void> openDevices(WidgetTester tester) async {
    await app.openTab(tester, HomeTab.settings);
    await tester.tap(find.byKey(const Key('devices')));
    await app.settle(tester);
  }

  /// Moves the clock and lets the screens' timers and requests run.
  Future<void> advance(WidgetTester tester, Duration by) async {
    now = now.add(by);
    await tester.pump(by);
    await tester.runAsync(pumpEventQueue);
    await tester.pump();
  }

  /// Lets the requests answer and the screen draw what they brought.
  Future<void> settle(WidgetTester tester) => app.settle(tester);
}
