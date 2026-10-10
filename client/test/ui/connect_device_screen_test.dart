import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/ui/pairing_code_view.dart';
import 'package:signalhub_client/src/ui/widgets/pairing_qr.dart';

import '../support/people_fixture.dart';
import '../support/screenshot.dart';

void main() {
  setUpAll(loadDesignFonts);

  late PeopleFixture f;

  Future<void> open(
    WidgetTester tester,
    String role, {
    Size size = const Size(412, 892),
    double textScale = 1,
  }) async {
    f = PeopleFixture(role);
    await f.start(tester, size: size, textScale: textScale);
    await f.openDevices(tester);
    await tester.tap(find.text('Connect a device'));
    await f.settle(tester);
  }

  Future<void> typeName(WidgetTester tester, String name) async {
    await tester.enterText(find.byKey(const Key('pairingName')), name);
    await tester.pump();
  }

  Future<void> showCode(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('showCode')));
    await tester.runAsync(pumpEventQueue);
    await tester.pump();
    await tester.pump();
  }

  /// The body of the last request to make a pairing code.
  Map<String, Object?> pairingBody() => jsonDecode(
    f.app.backend.requests
        .lastWhere(
          (r) => r.method == 'POST' && r.url.path.endsWith('/client/pairings'),
        )
        .body,
  ) as Map<String, Object?>;

  FilledButton showCodeButton(WidgetTester tester) =>
      tester.widget<FilledButton>(
        find.descendant(
          of: find.byKey(const Key('showCode')),
          matching: find.byType(FilledButton),
        ),
      );

  Future<void> poll(WidgetTester tester) async {
    await tester.pump(PairingCodeView.pollInterval);
    await tester.runAsync(pumpEventQueue);
    await tester.pump();
  }

  group('a Mod', () {
    testWidgets('names the new device, for themselves, in step one', (
      tester,
    ) async {
      await open(tester, 'MOD');

      expect(find.text('Connect a device'), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
      expect(find.text('For Ana (you).'), findsOneWidget);
      expect(find.text('Name of the new device'), findsWidgets);
      expect(
        find.text('1 to 100 characters. You can rename it later.'),
        findsOneWidget,
      );
      // No chooser: a mod is the only person it can be for.
      expect(find.text('For'), findsNothing);
      expect(find.byType(RadioGroup<String>), findsNothing);
      expect(showCodeButton(tester).onPressed, isNull);
      expect(find.text('Show code'), findsOneWidget);
      await typeName(tester, 'Ana - Phone 2');
      await tester.pumpAndSettle();
      await saveScreenshot(tester, find.byKey(screenshotKey), '3i0');
    });

    testWidgets('an empty name says so and keeps Show code off', (
      tester,
    ) async {
      await open(tester, 'MOD');
      expect(find.text('Enter a name.'), findsNothing);

      await typeName(tester, 'Ana - Phone 2');
      expect(showCodeButton(tester).onPressed, isNotNull);
      await typeName(tester, '   ');

      expect(find.text('Enter a name.'), findsOneWidget);
      expect(showCodeButton(tester).onPressed, isNull);
    });

    testWidgets('step two shows the code for them, with the warning', (
      tester,
    ) async {
      await open(tester, 'MOD');
      await typeName(tester, 'Ana - Phone 2');

      await showCode(tester);

      // For themselves: no user is named.
      expect(pairingBody(), {'name': 'Ana - Phone 2'});
      expect(
        find.textContaining(
          'For Ana (you). New device: Ana - Phone 2. Scan this in SignalHub '
          'on the other device, or open the link there.',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<PairingQr>(find.byType(PairingQr)).data,
        'signalhub://pair?server=https%3A%2F%2Fsignalhub.test'
        '&code=shpc1_fromDevice0xxxxxxx',
      );
      expect(
        find.textContaining('Works once. 10:00 left.', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Copy link'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(
        find.text(
          'Whoever uses this code gets a device of yours. Share it only with '
          'yourself.',
        ),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
      await saveScreenshot(tester, find.byKey(screenshotKey), '3i');
    });

    testWidgets('the code, used, says which device used it', (tester) async {
      await open(tester, 'MOD');
      await typeName(tester, 'Ana - Phone 2');
      await showCode(tester);

      f.people.usePairing('Ana - Phone 2');
      await poll(tester);

      expect(
        find.textContaining('Connected.', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          "Ana - Phone 2 used this code. It can't be used again.",
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(find.text('Done'), findsOneWidget);
      expect(find.textContaining('left.', findRichText: true), findsNothing);
      await tester.pumpAndSettle();
      await saveScreenshot(tester, find.byKey(screenshotKey), '3i3');

      await tester.tap(find.text('Done'));
      await f.settle(tester);

      // Back on Devices, with the device that joined listed.
      expect(find.widgetWithText(AppBar, 'Devices'), findsOneWidget);
      expect(find.text('Ana - Phone 2'), findsOneWidget);
    });

    testWidgets('a code that ran out is replaced by a new one', (tester) async {
      await open(tester, 'MOD');
      await typeName(tester, 'Ana - Phone 2');
      await showCode(tester);

      await f.advance(tester, const Duration(minutes: 10, seconds: 1));

      expect(find.text('This code ran out. Make a new one.'), findsOneWidget);
      await tester.pumpAndSettle();
      await saveScreenshot(tester, find.byKey(screenshotKey), '3i4-ran-out');

      f.people.pairingExpiresAt = f.now.add(const Duration(minutes: 10));
      await tester.tap(find.text('Make a new code'));
      await tester.runAsync(pumpEventQueue);
      await tester.pump();

      expect(f.people.pairingsMade, hasLength(2));
      expect(pairingBody(), {'name': 'Ana - Phone 2'});
      expect(find.text('This code ran out. Make a new one.'), findsNothing);
      expect(
        find.textContaining('10:00 left.', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('a role taken away says so and the screen is not theirs', (
      tester,
    ) async {
      await open(tester, 'MOD');
      await typeName(tester, 'Ana - Phone 2');
      f.app.backend.userRole = 'BASIC';

      await showCode(tester);
      await f.settle(tester);

      expect(find.text("Your role changed. You're now Basic."), findsOneWidget);
      expect(find.text("You can't open this"), findsOneWidget);
      expect(f.people.pairingsMade, isEmpty);
    });

    testWidgets('a server that cannot pair from a device says so', (
      tester,
    ) async {
      await open(tester, 'MOD');
      await typeName(tester, 'Ana - Phone 2');
      f.people.failWith = 404;

      await showCode(tester);

      expect(
        find.text(
          'This server cannot create pairing codes from a device. Update '
          'SignalHub, or create the code on the admin page.',
        ),
        findsOneWidget,
      );
      expect(find.byType(PairingQr), findsNothing);
    });

    testWidgets('no connection is said, and trying again works', (
      tester,
    ) async {
      await open(tester, 'MOD');
      await typeName(tester, 'Ana - Phone 2');
      f.people.failWith = 0;

      await showCode(tester);
      expect(
        find.text(
          "Couldn't make the code. Check your connection and try again.",
        ),
        findsOneWidget,
      );

      f.people.failWith = null;
      await showCode(tester);
      expect(find.byType(PairingQr), findsOneWidget);
    });
  });

  group('an admin', () {
    testWidgets('chooses who it is for: themselves or anyone not removed', (
      tester,
    ) async {
      f = PeopleFixture('ADMIN');
      f.people.userById('user-4')!.removed = true;
      await f.start(tester);
      await f.openDevices(tester);
      await tester.tap(find.text('Connect a device'));
      await f.settle(tester);

      expect(find.text('For'), findsOneWidget);
      // Yourself first, then everyone by name.
      final ids = ['user-0', 'user-2', 'user-3', 'user-5', 'user-1'];
      final tops = [
        for (final id in ids) tester.getTopLeft(find.byKey(Key('for-$id'))).dy,
      ];
      expect(tops, [...tops]..sort());
      // Removed people are not listed.
      expect(find.text('Marta'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('for-user-0')),
          matching: find.text('You'),
        ),
        findsOneWidget,
      );
      for (final (id, role) in [
        ('user-0', 'Admin'),
        ('user-1', 'Admin'),
        ('user-2', 'Mod'),
        ('user-3', 'Basic'),
      ]) {
        expect(
          find.descendant(
            of: find.byKey(Key('for-$id')),
            matching: find.text(role),
          ),
          findsOneWidget,
        );
      }
      expect(find.text('Name of the new device'), findsWidgets);
      expect(find.text('Show code'), findsOneWidget);
    });

    testWidgets(
      'a device for someone else names them in the button, the code and the warning',
      (tester) async {
        await open(tester, 'ADMIN');
        await tester.tap(find.byKey(const Key('for-user-2')));
        await tester.pump();
        await typeName(tester, 'Ana - Phone 2');
        expect(find.text('Show code for Ana'), findsOneWidget);
        await tester.pumpAndSettle();
        await saveScreenshot(tester, find.byKey(screenshotKey), '3i2');

        await showCode(tester);

        expect(pairingBody(), {'name': 'Ana - Phone 2', 'userId': 'user-2'});
        expect(
          find.textContaining(
            'For Ana. New device: Ana - Phone 2. Scan this in SignalHub on the '
            'other device, or open the link there.',
            findRichText: true,
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            "Whoever uses this code gets a device of Ana's. Share it only with "
            'Ana.',
          ),
          findsOneWidget,
        );
        await tester.pumpAndSettle();
        await saveScreenshot(tester, find.byKey(screenshotKey), '3i5');
      },
    );

    testWidgets('a device for themselves says "you"', (tester) async {
      await open(tester, 'ADMIN');
      await typeName(tester, 'Rodrigo - Laptop');

      await showCode(tester);

      expect(pairingBody(), {'name': 'Rodrigo - Laptop', 'userId': 'user-0'});
      expect(
        find.textContaining(
          'For Rodrigo (you). New device:',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Whoever uses this code gets a device of yours. Share it only with '
          'yourself.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('another admin can be chosen', (tester) async {
      await open(tester, 'ADMIN');
      await tester.tap(find.byKey(const Key('for-user-1')));
      await tester.pump();
      await typeName(tester, 'Sofia - Laptop');

      await showCode(tester);

      expect(pairingBody()['userId'], 'user-1');
    });

    for (final status in [409, 404]) {
      testWidgets(
        'a person removed meanwhile ($status) is said, and left out',
        (tester) async {
          await open(tester, 'ADMIN');
          await tester.tap(find.byKey(const Key('for-user-4')));
          await tester.pump();
          await typeName(tester, 'Marta - Phone 2');
          f.people
            ..userById('user-4')!.removed = true
            ..removedPairingStatus = status;

          await showCode(tester);
          await f.settle(tester);

          expect(
            find.text("Marta's access was removed. Choose someone else."),
            findsOneWidget,
          );
          expect(find.byKey(const Key('for-user-4')), findsNothing);
          expect(find.byType(PairingQr), findsNothing);
          // Back to themselves, to choose again.
          expect(find.text('Show code'), findsOneWidget);
          if (status == 409) {
            await tester.pumpAndSettle();
            await saveScreenshot(tester, find.byKey(screenshotKey), '3i4');
          }
        },
      );
    }

    testWidgets(
      'a code that ran out for someone removed goes back to step one',
      (tester) async {
        await open(tester, 'ADMIN');
        await tester.tap(find.byKey(const Key('for-user-4')));
        await tester.pump();
        await typeName(tester, 'Marta - Phone 2');
        await showCode(tester);
        await f.advance(tester, const Duration(minutes: 10, seconds: 1));
        f.people
          ..userById('user-4')!.removed = true
          ..pairingExpiresAt = f.now.add(const Duration(minutes: 10));

        await tester.tap(find.text('Make a new code'));
        await tester.runAsync(pumpEventQueue);
        await f.settle(tester);

        expect(
          find.text("Marta's access was removed. Choose someone else."),
          findsOneWidget,
        );
        expect(find.byKey(const Key('for-user-4')), findsNothing);
        // The name stays for the next choice.
        expect(
          tester
              .widget<TextField>(
                find.descendant(
                  of: find.byKey(const Key('pairingName')),
                  matching: find.byType(TextField),
                ),
              )
              .controller!
              .text,
          'Marta - Phone 2',
        );
      },
    );

    testWidgets('the warning for someone else carries to the used state', (
      tester,
    ) async {
      await open(tester, 'ADMIN');
      await tester.tap(find.byKey(const Key('for-user-2')));
      await tester.pump();
      await typeName(tester, 'Ana - Phone 2');
      await showCode(tester);

      f.people.usePairing('Ana - Phone 2');
      await poll(tester);

      expect(
        find.textContaining(
          "Ana - Phone 2 used this code. It can't be used again.",
          findRichText: true,
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'a role that is no longer admin is told, and no one is paired',
      (tester) async {
        await open(tester, 'ADMIN');
        await tester.tap(find.byKey(const Key('for-user-2')));
        await tester.pump();
        await typeName(tester, 'Ana - Phone 2');
        f.app.backend
          ..userRole = 'MOD'
          ..admin = false;

        await showCode(tester);
        await f.settle(tester);

        expect(
          find.text("Your role changed. You're now a Mod."),
          findsOneWidget,
        );
        expect(find.byType(PairingQr), findsNothing);
        expect(f.people.pairingsMade, isEmpty);
      },
    );

    testWidgets('at 360 dp and 200 % text neither step overflows', (
      tester,
    ) async {
      await open(tester, 'ADMIN', size: const Size(360, 900), textScale: 2);
      expect(tester.takeException(), isNull);

      await typeName(tester, 'Ana - Kitchen tablet, upstairs');
      await showCode(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(PairingQr), findsOneWidget);

      await f.advance(tester, const Duration(minutes: 11));
      expect(tester.takeException(), isNull);
    });
  });
}
