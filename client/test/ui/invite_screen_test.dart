import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/app_controller.dart';
import 'package:signalhub_client/src/ui/pairing_code_view.dart';
import 'package:signalhub_client/src/ui/widgets/copy_button.dart';
import 'package:signalhub_client/src/ui/widgets/pairing_qr.dart';

import '../support/fake_platform.dart';
import '../support/harness.dart';
import '../support/people_backend.dart';
import '../support/phone.dart';
import '../support/screenshot.dart';

void main() {
  setUpAll(loadDesignFonts);

  late AppHarness app;
  late PeopleBackend people;
  late FakePlatform platform;
  late DateTime now;

  /// An admin's device, with the people of the design, on a clock the test
  /// moves. A code made now lasts ten minutes.
  Future<void> openInvite(
    WidgetTester tester, {
    Size size = const Size(412, 892),
    double textScale = 1,
  }) async {
    app = AppHarness(role: 'ADMIN');
    people = PeopleBackend(app.backend);
    now = DateTime.utc(2026, 10, 10, 12);
    app.controller.clock = () => now;
    people
      ..seedDesignData(now)
      // Rui is the person these tests invite.
      ..users.removeWhere((u) => u.name == 'Rui')
      ..pairingExpiresAt = now.add(const Duration(minutes: 10));
    platform = FakePlatform(tester);
    useDesignPhone(tester, size: size, textScale: textScale);
    await app.start(tester);
    await app.openTab(tester, HomeTab.people);
    await tester.tap(find.text('Invite'));
    await app.settle(tester);
  }

  Future<void> advance(WidgetTester tester, Duration by) async {
    now = now.add(by);
    await tester.pump(by);
    await tester.runAsync(pumpEventQueue);
    await tester.pump();
  }

  Future<void> typeName(WidgetTester tester, String name) async {
    await tester.enterText(find.byKey(const Key('inviteName')), name);
    await tester.pump();
  }

  Future<void> make(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('makeInvitation')));
    await tester.runAsync(pumpEventQueue);
    await tester.pump();
    await tester.pump();
  }

  FilledButton makeButton(WidgetTester tester) => tester.widget<FilledButton>(
    find.descendant(
      of: find.byKey(const Key('makeInvitation')),
      matching: find.byType(FilledButton),
    ),
  );

  Future<void> openCode(WidgetTester tester, {String name = 'Rui'}) async {
    await openInvite(tester);
    await typeName(tester, name);
    await make(tester);
  }

  group('the form', () {
    testWidgets('asks for a name, Basic or Mod and a first device name', (
      tester,
    ) async {
      await openInvite(tester);

      expect(find.text('Invite someone'), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
      expect(find.text('Their name'), findsWidgets);
      expect(find.text('First device name (optional)'), findsWidgets);
      // The device name starts as the server's own default.
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const Key('inviteDevice')),
                matching: find.byType(TextField),
              ),
            )
            .controller!
            .text,
        'First device',
      );
      expect(find.text('Basic'), findsOneWidget);
      expect(find.text('Mod'), findsOneWidget);
      expect(find.text('Admin'), findsNothing);
      expect(
        find.text(
          'Basic: their own producers and subscriptions. Mod: also pairs and '
          'removes their own devices.',
        ),
        findsOneWidget,
      );
      expect(find.text('Make invitation'), findsOneWidget);
      // No code exists before the invitation is made.
      expect(find.byType(PairingQr), findsNothing);
      expect(people.pairingsMade, isEmpty);
      await tester.pump(const Duration(seconds: 1));
      await saveScreenshot(tester, find.byKey(screenshotKey), '3d0');
    });

    testWidgets('an empty name is said and keeps the button off', (
      tester,
    ) async {
      await openInvite(tester);
      // Nothing typed yet: no error to scold, and the button is off.
      expect(find.text('Enter their name.'), findsNothing);
      expect(makeButton(tester).onPressed, isNull);

      await typeName(tester, 'Rui');
      expect(makeButton(tester).onPressed, isNotNull);
      await typeName(tester, '  ');

      expect(find.text('Enter their name.'), findsOneWidget);
      expect(makeButton(tester).onPressed, isNull);
    });

    testWidgets('a name that is taken is said, whatever the capitals', (
      tester,
    ) async {
      await openInvite(tester);
      await typeName(tester, 'ana');
      await make(tester);

      expect(
        find.text('Someone on this server already has that name. Use another.'),
        findsOneWidget,
      );
      expect(makeButton(tester).onPressed, isNull);
      expect(find.byType(PairingQr), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      await saveScreenshot(tester, find.byKey(screenshotKey), '3d2');

      // Another name works again; so does the same one in other capitals
      // only once the server has said so.
      await typeName(tester, 'Ana Maria');
      expect(
        find.text('Someone on this server already has that name. Use another.'),
        findsNothing,
      );
      expect(makeButton(tester).onPressed, isNotNull);
      // The server compares ignoring case, and so does the app.
      await typeName(tester, 'ANA');
      expect(makeButton(tester).onPressed, isNull);
    });

    testWidgets('Close leaves the screen', (tester) async {
      await openInvite(tester);

      await tester.tap(find.byTooltip('Close'));
      await app.settle(tester);

      expect(find.text('Invite someone'), findsNothing);
      expect(find.widgetWithText(AppBar, 'People'), findsOneWidget);
    });

    testWidgets('a failure is said and the form stays', (tester) async {
      await openInvite(tester);
      people.failWith = 0;
      await typeName(tester, 'Rui');

      await make(tester);

      expect(
        find.text(
          "Couldn't make the invitation. Check your connection and try again.",
        ),
        findsOneWidget,
      );
      expect(makeButton(tester).onPressed, isNotNull);

      people.failWith = null;
      await make(tester);
      expect(find.byType(PairingQr), findsOneWidget);
      expect(
        find.text(
          "Couldn't make the invitation. Check your connection and try again.",
        ),
        findsNothing,
      );
    });

    testWidgets('the screen follows a role that is no longer admin', (
      tester,
    ) async {
      await openInvite(tester);
      await typeName(tester, 'Zeca');
      app.backend
        ..userRole = 'MOD'
        ..admin = false;

      await make(tester);
      await app.settle(tester);

      expect(
        find.text('This screen is not available to your role'),
        findsOneWidget,
      );
      expect(find.text("Your role changed. You're now a Mod."), findsOneWidget);
      // Not tried again, and nobody was invited.
      expect(people.users.where((u) => u.name == 'Zeca'), isEmpty);
    });
  });

  group('the code', () {
    testWidgets('shows the QR, the countdown, the link and who it is for', (
      tester,
    ) async {
      await openCode(tester);

      final body = jsonDecode(
        (app.backend.requests.lastWhere(
          (r) => r.method == 'POST' && r.url.path.endsWith('/client/users'),
        )).body,
      ) as Map<String, Object?>;
      expect(body, {
        'name': 'Rui',
        'role': 'BASIC',
        'deviceName': 'First device',
      });
      expect(find.text('Invite someone'), findsOneWidget);
      expect(
        find.textContaining(
          'Invitation for Rui · Basic · first device',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('“First device”', findRichText: true),
        findsOneWidget,
      );
      final qr = tester.widget<PairingQr>(find.byType(PairingQr));
      expect(
        qr.data,
        'signalhub://pair?server=https%3A%2F%2Fsignalhub.test'
        '&code=shpc1_fromDevice0xxxxxxx',
      );
      expect(
        find.textContaining(
          'Rui scans this in SignalHub on their phone.',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('10:00 left.', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Copy link'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(
        find.text(
          'Whoever uses this code joins as Rui. Share it only with Rui.',
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Pairing QR code'), findsOneWidget);
      // The invitation exists and Rui is listed, not yet paired.
      expect(people.userById('user-5')?.name, 'Rui');
      await tester.pump(const Duration(seconds: 1));
      await saveScreenshot(tester, find.byKey(screenshotKey), '3d');
    });

    testWidgets('a Mod invitation and a typed device name are sent', (
      tester,
    ) async {
      await openInvite(tester);
      await typeName(tester, 'Luna');
      await tester.tap(find.text('Mod'));
      await tester.pump();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('inviteDevice')),
          matching: find.byType(TextField),
        ),
        'Luna - iPhone',
      );
      await make(tester);

      final body = jsonDecode(
        app.backend.requests
            .lastWhere(
              (r) => r.method == 'POST' && r.url.path.endsWith('/client/users'),
            )
            .body,
      ) as Map<String, Object?>;
      expect(body, {
        'name': 'Luna',
        'role': 'MOD',
        'deviceName': 'Luna - iPhone',
      });
      expect(
        find.textContaining(
          'Invitation for Luna · Mod · first device',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('“Luna - iPhone”', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('an empty device name leaves the server its default', (
      tester,
    ) async {
      await openInvite(tester);
      await typeName(tester, 'Luna');
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('inviteDevice')),
          matching: find.byType(TextField),
        ),
        '',
      );
      await make(tester);

      final body = jsonDecode(
        app.backend.requests
            .lastWhere(
              (r) => r.method == 'POST' && r.url.path.endsWith('/client/users'),
            )
            .body,
      ) as Map<String, Object?>;
      expect(body.containsKey('deviceName'), isFalse);
    });

    testWidgets('Copy link copies the link and Share shares it as text', (
      tester,
    ) async {
      await openCode(tester);
      final link = tester.widget<PairingQr>(find.byType(PairingQr)).data;

      await tester.tap(find.byType(CopyButton));
      await tester.pump();
      expect(platform.copied, [link]);
      expect(find.text('Copied'), findsOneWidget);

      await tester.tap(find.byKey(const Key('shareLink')));
      await tester.pump();
      expect(platform.shared, [link]);
    });

    testWidgets('a share sheet that does not open says so', (tester) async {
      await openCode(tester);
      platform.shareFails = true;

      await tester.tap(find.byKey(const Key('shareLink')));
      await tester.pump();
      await tester.pump();

      expect(
        find.textContaining("Couldn't open the share sheet"),
        findsOneWidget,
      );
    });

    testWidgets('the link and the countdown are read as plain words', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await openCode(tester);

      expect(find.bySemanticsLabel('Pairing QR code'), findsOneWidget);
      expect(find.bySemanticsLabel('Pairing link'), findsOneWidget);
      expect(find.bySemanticsLabel('Copy link'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('the countdown counts down', (tester) async {
      await openCode(tester);

      await advance(tester, const Duration(seconds: 61));
      expect(
        find.textContaining('8:59 left.', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('a server with no public address gets the app\'s own link', (
      tester,
    ) async {
      await openInvite(tester);
      people.pairingUris = false;
      await typeName(tester, 'Rui');
      await make(tester);

      expect(
        tester.widget<PairingQr>(find.byType(PairingQr)).data,
        'signalhub://pair?server=https%3A%2F%2Fsignalhub.test'
        '&code=shpc1_fromDevice0xxxxxxx',
      );
    });
  });

  group('while the code is shown', () {
    int asked() => people.requests
        .where((r) => r.startsWith('GET /api/v1/client/pairings/'))
        .length;

    Future<void> poll(WidgetTester tester) async {
      await tester.pump(PairingCodeView.pollInterval);
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
    }

    testWidgets('it asks every 2.5 seconds, and shows who joined', (
      tester,
    ) async {
      await openCode(tester);

      await poll(tester);
      await poll(tester);
      expect(asked(), 2);
      expect(find.textContaining('joined', findRichText: true), findsNothing);

      people.usePairing('Rui - iPhone');
      await poll(tester);

      expect(
        find.textContaining('Rui joined', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          "on Rui - iPhone. The code can't be used again.",
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(find.textContaining('left.', findRichText: true), findsNothing);
      expect(find.text('Done'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await saveScreenshot(tester, find.byKey(screenshotKey), '3d3');
      // Nothing more is asked once it is known.
      final before = asked();
      await poll(tester);
      await poll(tester);
      expect(asked(), before);
    });

    testWidgets('Done leaves the screen, and People lists who joined', (
      tester,
    ) async {
      await openCode(tester);
      people.usePairing('Rui - iPhone');
      await poll(tester);

      await tester.tap(find.text('Done'));
      await tester.runAsync(pumpEventQueue);
      await app.settle(tester);

      expect(find.text('Invite someone'), findsNothing);
      expect(find.byKey(const Key('person-user-5')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('person-user-5')),
          matching: find.text('1 device'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('it stops asking when the screen is left', (tester) async {
      await openCode(tester);
      await poll(tester);
      final before = asked();

      await tester.tap(find.byTooltip('Close'));
      await app.settle(tester);
      await poll(tester);
      await poll(tester);

      expect(asked(), before);
    });

    testWidgets('it does not ask while the app is in the background', (
      tester,
    ) async {
      await openCode(tester);

      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await poll(tester);
      await poll(tester);
      expect(asked(), 0);

      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await poll(tester);
      expect(asked(), 1);
    });

    testWidgets('a server that cannot say stops being asked', (tester) async {
      await openCode(tester);
      people.failWith = 404;

      await poll(tester);
      await poll(tester);
      await poll(tester);

      // Asked once, then not again: the code is still shown.
      expect(asked(), 1);
      expect(find.byType(PairingQr), findsOneWidget);
    });
  });

  group('when the code runs out', () {
    testWidgets('says so, and Make a new code makes one for the same person', (
      tester,
    ) async {
      await openCode(tester);

      await advance(tester, const Duration(minutes: 10, seconds: 1));

      expect(
        find.text(
          'This code ran out. Make a new one for Rui; the old one no longer works.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('left.', findRichText: true), findsNothing);
      expect(
        find.text(
          'Leaving now keeps Rui in the list as "Invited · not paired yet". '
          'Open Rui any time and choose "Pair a device for Rui".',
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 1));
      await saveScreenshot(tester, find.byKey(screenshotKey), '3d4');

      people.pairingExpiresAt = now.add(const Duration(minutes: 10));
      await tester.tap(find.text('Make a new code'));
      await tester.runAsync(pumpEventQueue);
      await tester.pump();

      expect(people.pairingsMade, hasLength(2));
      expect(people.pairingsMade.last, (
        name: 'First device',
        userId: 'user-5',
      ));
      expect(
        find.text(
          'This code ran out. Make a new one for Rui; the old one no longer works.',
        ),
        findsNothing,
      );
    });

    testWidgets('it asks once more as the code runs out', (tester) async {
      await openCode(tester);
      int asked() => people.requests
          .where((r) => r.startsWith('GET /api/v1/client/pairings/'))
          .length;
      final before = asked();

      people.usePairing('Rui - iPhone');
      await advance(tester, const Duration(minutes: 10, seconds: 1));

      // Used in its last seconds: it says so rather than that it ran out.
      expect(asked(), greaterThan(before));
      expect(
        find.textContaining('Rui joined', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets(
      'screen readers hear the countdown at a minute and at the end',
      (tester) async {
        await openCode(tester);

        await advance(tester, const Duration(minutes: 5));
        await advance(tester, const Duration(minutes: 3, seconds: 59));
        expect(platform.announced, isEmpty);

        // A minute is left: said once, not every second after.
        await advance(tester, const Duration(seconds: 1));
        await advance(tester, const Duration(seconds: 20));
        await advance(tester, const Duration(seconds: 20));
        expect(platform.announced, ['1 minute left to use this code.']);

        await advance(tester, const Duration(seconds: 40));
        await advance(tester, const Duration(seconds: 5));
        expect(platform.announced, [
          '1 minute left to use this code.',
          'This code ran out.',
        ]);
      },
    );
  });

  group('layout', () {
    testWidgets('at 360 dp and 200 % text neither step overflows', (
      tester,
    ) async {
      await openInvite(tester, size: const Size(360, 900), textScale: 2);
      expect(tester.takeException(), isNull);

      await typeName(tester, 'Maria de Fátima Albuquerque');
      await make(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(PairingQr), findsOneWidget);

      await advance(tester, const Duration(minutes: 11));
      expect(tester.takeException(), isNull);
      expect(find.text('Make a new code'), findsOneWidget);
    });
  });
}
