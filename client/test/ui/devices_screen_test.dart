import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/app_controller.dart';
import 'package:signalhub_client/src/models/client_registration.dart';
import 'package:signalhub_client/src/ui/devices_screen.dart';
import 'package:signalhub_client/src/ui/widgets/pairing_qr.dart';

import '../support/people_backend.dart';
import '../support/people_fixture.dart';
import '../support/screenshot.dart';

const thisDevice = '01a0da2c-1f3e-7a51-8d0c-6b1f2e3d4c5b';

void main() {
  setUpAll(loadDesignFonts);

  Finder device(String id) => find.byKey(Key('device-$id'));
  Finder inRow(String id, Finder matching) =>
      find.descendant(of: device(id), matching: matching);

  /// The words of a row: its name, its tags and its second line.
  List<String> words(String id) => [
    for (final text
        in find
            .descendant(of: device(id), matching: find.byType(Text))
            .evaluate()
            .map((e) => (e.widget as Text).data))
      ?text,
  ];

  Future<void> openMenu(WidgetTester tester, String name) async {
    await tester.scrollUntilVisible(
      find.byTooltip('More actions for $name'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More actions for $name'));
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('confirm')));
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
  }

  /// A device that is a browser: the server cannot say so yet, so the list
  /// it read is shown again with one of its devices as a browser.
  void makeBrowser(PeopleFixture f, String id) {
    final devices = f.controller.deviceList.devices;
    f.controller.deviceList.show([
      for (final d in devices)
        if (d.id == id)
          ManagedDevice(
            id: d.id,
            name: d.name,
            admin: d.admin,
            createdAt: d.createdAt,
            user: d.user,
            lastActiveAt: d.lastActiveAt,
            revokedAt: d.revokedAt,
            isBrowser: true,
          )
        else
          d,
    ]);
  }

  group('a Basic user', () {
    late PeopleFixture f;

    Future<void> open(WidgetTester tester) async {
      f = PeopleFixture('BASIC');
      await f.start(tester);
      await f.openDevices(tester);
    }

    testWidgets('sees their own devices, read only, and who can help', (
      tester,
    ) async {
      await open(tester);

      expect(find.widgetWithText(AppBar, 'Devices'), findsOneWidget);
      expect(words(thisDevice), ['Pixel 8', 'This device']);
      expect(words('d-tablet'), ['João - Tablet', 'Last active 3 days ago']);
      expect(words('d-old'), ['João - Old phone', 'Revoked', 'Revoked 4 Oct']);
      // Nobody else's.
      expect(find.text('Rodrigo - Tablet'), findsNothing);
      expect(find.text('João - Galaxy'), findsNothing);
      expect(
        find.text('To add or remove a device, ask an admin of this server.'),
        findsOneWidget,
      );
      // What this role cannot do is not drawn, not greyed.
      expect(find.text('Connect a device'), findsNothing);
      expect(find.byType(PopupMenuButton<Object?>), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      expect(find.text('Rename'), findsNothing);
      expect(find.text('Revoke'), findsNothing);
      expect(find.text('Delete'), findsNothing);
      await saveScreenshot(tester, find.byKey(screenshotKey), '3g');
    });

    testWidgets('the revoked device is greyed and has no actions', (
      tester,
    ) async {
      await open(tester);

      expect(
        tester
            .widget<Opacity>(
              find.ancestor(
                of: find.text('João - Old phone'),
                matching: find.byType(Opacity),
              ),
            )
            .opacity,
        lessThan(1),
      );
      expect(inRow('d-old', find.byType(IconButton)), findsNothing);
    });

    testWidgets('signs out their own browser after asking, as a button', (
      tester,
    ) async {
      f = PeopleFixture('BASIC');
      f.people
        ..addDevice(
          'd-browser',
          'Firefox on Linux',
          PeopleBackend.callerId,
          lastActive: f.now,
        )
        // Not today's server, which refuses a basic user every change.
        ..browsers.add('d-browser');
      final semantics = tester.ensureSemantics();
      await f.start(tester);
      await f.openDevices(tester);
      makeBrowser(f, 'd-browser');
      await tester.pumpAndSettle();

      expect(words('d-browser'), [
        'Firefox on Linux',
        'Browser',
        'Last active today',
        'Sign out',
      ]);
      expect(find.byIcon(Icons.language), findsOneWidget);
      // The phones in the list have no such button.
      expect(inRow('d-tablet', find.text('Sign out')), findsNothing);
      expect(
        find.bySemanticsLabel('Sign out Firefox on Linux'),
        findsOneWidget,
      );
      semantics.dispose();

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      expect(find.text('Sign out Firefox on Linux?'), findsOneWidget);
      expect(
        find.text(
          'This browser stops being a device of yours. To sign in again, '
          'scan a new code from this app.',
        ),
        findsOneWidget,
      );
      await saveScreenshot(tester, find.byKey(screenshotKey), '3g2');
      // An ordinary action, so a primary text button and not an error one.
      final action = tester.widget<TextButton>(
        find.byKey(const Key('confirm')),
      );
      expect(
        action.style?.foregroundColor?.resolve({}),
        isNull,
        reason: 'signing out is not drawn in the error colour',
      );

      await confirm(tester);

      expect(
        f.people.devices.firstWhere((d) => d['id'] == 'd-browser')['revokedAt'],
        isNotNull,
      );
      expect(inRow('d-browser', find.text('Revoked')), findsOneWidget);
      expect(inRow('d-browser', find.text('Sign out')), findsNothing);
    });

    testWidgets('a server that refuses a basic user the sign-out says so', (
      tester,
    ) async {
      // Today's server refuses every device change from a basic user.
      f = PeopleFixture('BASIC');
      f.people.addDevice(
        'd-browser',
        'Firefox on Linux',
        PeopleBackend.callerId,
      );
      await f.start(tester);
      await f.openDevices(tester);
      makeBrowser(f, 'd-browser');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await confirm(tester);

      expect(
        find.text("Your role doesn't allow that. Ask an admin of this server."),
        findsOneWidget,
      );
      expect(inRow('d-browser', find.text('Revoked')), findsNothing);
    });

    testWidgets('a browser in use is This browser and has no Sign out', (
      tester,
    ) async {
      f = PeopleFixture('BASIC');
      f.app.backend.lastActiveAt = f.now.toIso8601String();
      await f.start(tester);
      await f.openDevices(tester);
      makeBrowser(f, thisDevice);
      await tester.pumpAndSettle();

      expect(words(thisDevice), [
        'Pixel 8',
        'This browser',
        'Last active today',
      ]);
    });

    testWidgets('the list is read when the screen opens and on pull', (
      tester,
    ) async {
      await open(tester);
      int reads() => f.people.requests
          .where((r) => r == 'GET /api/v1/client/devices')
          .length;
      final before = reads();

      f.people.addDevice('d-new', 'João - Laptop', PeopleBackend.callerId);
      await tester.fling(find.text('Pixel 8'), const Offset(0, 400), 1000);
      await f.settle(tester);

      expect(reads(), before + 1);
      expect(find.text('João - Laptop'), findsOneWidget);
    });
  });

  group('a Mod', () {
    late PeopleFixture f;

    Future<void> open(WidgetTester tester) async {
      f = PeopleFixture('MOD');
      await f.start(tester);
      await f.openDevices(tester);
    }

    testWidgets('sees their own, with Connect a device at the top', (
      tester,
    ) async {
      await open(tester);

      expect(find.text('Connect a device'), findsOneWidget);
      expect(
        find.text('Pair a new device with a one-time code'),
        findsOneWidget,
      );
      expect(find.text('Yours'), findsOneWidget);
      expect(words(thisDevice), ['Pixel 8', 'This device']);
      expect(words('d-tablet'), ['Ana - Tablet', 'Last active 3 days ago']);
      expect(find.text('Rodrigo - Tablet'), findsNothing);
      expect(
        find.text('To add or remove a device, ask an admin of this server.'),
        findsNothing,
      );
      // A menu on each device that can change, named for it.
      expect(find.byTooltip('More actions for Ana - Tablet'), findsOneWidget);
      expect(find.byTooltip('More actions for Pixel 8'), findsOneWidget);
      expect(find.byTooltip('More actions for Ana - Old phone'), findsNothing);
      await saveScreenshot(tester, find.byKey(screenshotKey), '3f');
    });

    testWidgets('the row menus are named for their device', (tester) async {
      final semantics = tester.ensureSemantics();
      await open(tester);

      expect(
        tester
            .getSemantics(find.byTooltip('More actions for Ana - Tablet'))
            .tooltip,
        'More actions for Ana - Tablet',
      );
      semantics.dispose();
    });

    testWidgets(
      'the menu has Rename and Revoke, but not Revoke on the device in use',
      (tester) async {
        await open(tester);

        await openMenu(tester, 'Ana - Tablet');
        expect(find.text('Rename'), findsOneWidget);
        expect(find.text('Revoke'), findsOneWidget);
        await tester.tapAt(const Offset(5, 400));
        await tester.pumpAndSettle();

        await openMenu(tester, 'Pixel 8');
        expect(find.text('Rename'), findsOneWidget);
        expect(find.text('Revoke'), findsNothing);
      },
    );

    testWidgets('renames a device', (tester) async {
      await open(tester);
      await openMenu(tester, 'Ana - Tablet');
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      expect(find.text('Rename device'), findsOneWidget);
      expect(
        find.text(
          '1 to 100 characters. The device keeps working. Nobody is notified.',
        ),
        findsOneWidget,
      );
      await saveScreenshot(tester, find.byKey(screenshotKey), '3h2');
      await tester.enterText(
        find.byKey(const Key('deviceName')),
        'Ana - Kitchen tablet',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('saveName')));
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();

      expect(find.text('Ana - Kitchen tablet'), findsOneWidget);
      expect(find.text('Ana - Tablet'), findsNothing);
      expect(
        f.people.devices.firstWhere((d) => d['id'] == 'd-tablet')['name'],
        'Ana - Kitchen tablet',
      );
    });

    testWidgets('an empty name is said and keeps Save off', (tester) async {
      await open(tester);
      await openMenu(tester, 'Ana - Tablet');
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('deviceName')), '  ');
      await tester.pump();

      expect(find.text('Enter a name.'), findsOneWidget);
      expect(
        tester.widget<TextButton>(find.byKey(const Key('saveName'))).onPressed,
        isNull,
      );
    });

    testWidgets('keeping the name asks nothing of the server', (tester) async {
      await open(tester);
      await openMenu(tester, 'Ana - Tablet');
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('saveName')));
      await tester.pumpAndSettle();

      expect(f.people.requests.where((r) => r.startsWith('PATCH')), isEmpty);
    });

    testWidgets('a rename that fails says so and can be retried', (
      tester,
    ) async {
      await open(tester);
      await openMenu(tester, 'Ana - Tablet');
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('deviceName')), 'Kitchen');
      await tester.pump();
      f.people.failWith = 0;
      await tester.tap(find.byKey(const Key('saveName')));
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();

      expect(
        find.text(
          "Couldn't rename Ana - Tablet. Check your connection and try again.",
        ),
        findsOneWidget,
      );
      expect(find.text('Ana - Tablet'), findsOneWidget);

      f.people.failWith = null;
      await tester.tap(find.text('Retry'));
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();

      expect(find.text('Kitchen'), findsOneWidget);
    });

    testWidgets('revokes a device after asking, naming it in full', (
      tester,
    ) async {
      await open(tester);
      await openMenu(tester, 'Ana - Tablet');
      await tester.tap(find.text('Revoke'));
      await tester.pumpAndSettle();

      expect(find.text('Revoke Ana - Tablet?'), findsOneWidget);
      expect(
        find.text(
          "It stops getting events at once and can't be used again. To use "
          'it again, you have to connect it with a new code. Your other '
          'devices and the admins are told.',
        ),
        findsOneWidget,
      );
      // The action cannot be taken back: an error-coloured text button.
      final action = tester.widget<TextButton>(
        find.byKey(const Key('confirm')),
      );
      final colors = Theme.of(tester.element(find.byKey(const Key('confirm'))))
          .colorScheme;
      expect(action.style?.foregroundColor?.resolve({}), colors.error);
      await saveScreenshot(tester, find.byKey(screenshotKey), '3h3');

      await confirm(tester);

      expect(inRow('d-tablet', find.text('Revoked')), findsOneWidget);
      expect(inRow('d-tablet', find.text('Revoked 10 Oct')), findsOneWidget);
      expect(
        f.people.devices.firstWhere((d) => d['id'] == 'd-tablet')['revokedAt'],
        isNotNull,
      );
      // A revoked device offers only Delete.
      expect(find.byTooltip('More actions for Ana - Tablet'), findsNothing);
      expect(inRow('d-tablet', find.text('Delete')), findsOneWidget);
    });

    testWidgets('Cancel revokes nothing', (tester) async {
      await open(tester);
      await openMenu(tester, 'Ana - Tablet');
      await tester.tap(find.text('Revoke'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(f.people.requests.where((r) => r.contains('revoke')), isEmpty);
    });

    testWidgets('the last active device cannot be revoked, and says so', (
      tester,
    ) async {
      await open(tester);
      f.people.refuseLastActive = true;
      await openMenu(tester, 'Ana - Tablet');
      await tester.tap(find.text('Revoke'));
      await tester.pumpAndSettle();
      await confirm(tester);

      expect(find.text("Can't revoke this device"), findsOneWidget);
      expect(
        find.text(
          "It's your last active device. Revoking it would lock you out. "
          'Connect another device first.',
        ),
        findsOneWidget,
      );
      await saveScreenshot(tester, find.byKey(screenshotKey), '3f2');
      expect(inRow('d-tablet', find.text('Revoked')), findsNothing);

      // Connect a device opens the connect screen.
      await tester.tap(find.text('Connect a device').last);
      await tester.pumpAndSettle();
      expect(find.text('Name of the new device'), findsWidgets);
    });

    testWidgets('Not now closes the explanation and keeps the list', (
      tester,
    ) async {
      await open(tester);
      f.people.refuseLastActive = true;
      await openMenu(tester, 'Ana - Tablet');
      await tester.tap(find.text('Revoke'));
      await tester.pumpAndSettle();
      await confirm(tester);

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(find.text("Can't revoke this device"), findsNothing);
      expect(find.text('Ana - Tablet'), findsOneWidget);
    });

    testWidgets('deletes a revoked device after asking', (tester) async {
      await open(tester);

      await tester.tap(inRow('d-old', find.text('Delete')));
      await tester.pumpAndSettle();

      expect(find.text('Delete Ana - Old phone?'), findsOneWidget);
      expect(
        find.text(
          'It is removed from the list with its push history. Events stay. '
          "This can't be undone, and nobody is notified.",
        ),
        findsOneWidget,
      );
      await saveScreenshot(tester, find.byKey(screenshotKey), '3h4');
      await confirm(tester);

      expect(find.text('Ana - Old phone'), findsNothing);
      expect(f.people.devices.any((d) => d['id'] == 'd-old'), isFalse);
    });

    testWidgets('a browser is named Sign out in its menu and its question', (
      tester,
    ) async {
      f = PeopleFixture('MOD');
      f.people.addDevice(
        'd-browser',
        'Firefox on Linux',
        PeopleBackend.callerId,
        lastActive: f.now,
      );
      await f.start(tester);
      await f.openDevices(tester);
      makeBrowser(f, 'd-browser');
      await tester.pumpAndSettle();

      expect(words('d-browser'), [
        'Firefox on Linux',
        'Browser',
        'Last active today',
      ]);
      await openMenu(tester, 'Firefox on Linux');
      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Revoke'), findsNothing);
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      expect(find.text('Sign out Firefox on Linux?'), findsOneWidget);
    });

    testWidgets('a device that an admin removed meanwhile leaves the list', (
      tester,
    ) async {
      await open(tester);
      f.people.devices.removeWhere((d) => d['id'] == 'd-tablet');
      await openMenu(tester, 'Ana - Tablet');
      await tester.tap(find.text('Revoke'));
      await tester.pumpAndSettle();
      await confirm(tester);

      expect(find.text('That device was already removed.'), findsOneWidget);
      expect(find.text('Ana - Tablet'), findsNothing);
    });

    testWidgets('a role taken away is said once, the screen follows it', (
      tester,
    ) async {
      await open(tester);
      f.app.backend.userRole = 'BASIC';

      await openMenu(tester, 'Ana - Tablet');
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('deviceName')), 'Kitchen');
      await tester.pump();
      await tester.tap(find.byKey(const Key('saveName')));
      await tester.runAsync(pumpEventQueue);
      await f.settle(tester);

      // The shell says so once; the screen is a Basic user's now.
      expect(find.text("Your role changed. You're now Basic."), findsOneWidget);
      expect(find.text('Connect a device'), findsNothing);
      expect(find.byTooltip('More actions for Ana - Tablet'), findsNothing);
      expect(
        find.text('To add or remove a device, ask an admin of this server.'),
        findsOneWidget,
      );
      // The refused change is not tried again, and says nothing more.
      expect(
        f.people.requests.where((r) => r.startsWith('PATCH')),
        hasLength(1),
      );
      expect(
        find.text("Your role doesn't allow that. Ask an admin of this server."),
        findsNothing,
      );
      await saveScreenshot(tester, find.byKey(screenshotKey), '3k');
    });

    testWidgets('a 403 whose role did not change says so in words', (
      tester,
    ) async {
      await open(tester);
      f.people.failWith = 403;

      await openMenu(tester, 'Ana - Tablet');
      await tester.tap(find.text('Revoke'));
      await tester.pumpAndSettle();
      await confirm(tester);

      expect(
        find.text("Your role doesn't allow that. Ask an admin of this server."),
        findsOneWidget,
      );
    });
  });

  group('an admin', () {
    late PeopleFixture f;

    Future<void> open(
      WidgetTester tester, {
      Size size = const Size(412, 892),
      double textScale = 1,
      Brightness brightness = Brightness.dark,
    }) async {
      f = PeopleFixture('ADMIN');
      await f.start(
        tester,
        size: size,
        textScale: textScale,
        brightness: brightness,
      );
      await f.openDevices(tester);
    }

    testWidgets('sees everyone\'s devices, grouped by person with the role', (
      tester,
    ) async {
      await open(tester);

      expect(find.text('Connect a device'), findsOneWidget);
      expect(find.text('For you or for someone else'), findsOneWidget);
      // You first, then the other admin, then mods, then basic users.
      final names = ['Rodrigo', 'Sofia', 'Ana', 'João', 'Marta'];
      final tops = [
        for (final n in names) tester.getTopLeft(find.text(n).first).dy,
      ];
      expect(tops, [...tops]..sort());
      for (final tag in ['Admin', 'Mod', 'Basic']) {
        expect(find.text(tag), findsWidgets);
      }
      expect(words('d-ana-pixel'), ['Ana - Pixel', 'Last active today']);
      expect(words('d-ana-tablet'), ['Ana - Tablet', 'Last active 3 days ago']);
      expect(words('d-joao'), ['João - Galaxy', 'Not used yet']);
      await saveScreenshot(tester, find.byKey(screenshotKey), '3h');
    });

    testWidgets('admin devices have no menu and say so', (tester) async {
      await open(tester);

      expect(words(thisDevice), ['Pixel 8', 'Admin device', 'This device']);
      expect(words('d-tablet'), [
        'Rodrigo - Tablet',
        'Admin device',
        'Last active today',
      ]);
      expect(words('d-sofia'), [
        'Sofia - Pixel',
        'Admin device',
        'Last active today',
      ]);
      expect(find.byTooltip('More actions for Rodrigo - Tablet'), findsNothing);
      expect(find.byTooltip('More actions for Sofia - Pixel'), findsNothing);
      expect(find.byTooltip('More actions for Pixel 8'), findsNothing);
    });

    testWidgets('a revoked device is greyed, tells when, and offers Delete', (
      tester,
    ) async {
      await open(tester);

      expect(words('d-ana-old'), [
        'Ana - Old phone',
        'Revoked',
        'Revoked 4 Oct',
        'Delete',
      ]);
      expect(find.byTooltip('More actions for Ana - Old phone'), findsNothing);
      // After the person's active devices.
      expect(
        tester.getTopLeft(find.text('Ana - Old phone')).dy,
        greaterThan(tester.getTopLeft(find.text('Ana - Tablet')).dy),
      );
    });

    testWidgets('revokes a device of someone else, and says who is told', (
      tester,
    ) async {
      await open(tester);
      await openMenu(tester, 'Ana - Tablet');
      await saveScreenshot(tester, find.byKey(screenshotKey), '3h-menu');
      await tester.tap(find.text('Revoke'));
      await tester.pumpAndSettle();

      expect(find.text('Revoke Ana - Tablet?'), findsOneWidget);
      expect(
        find.text(
          "It stops getting events at once and can't be used again. To use "
          "it again, Ana has to connect it with a new code. Ana's other "
          'devices and the admins are told.',
        ),
        findsOneWidget,
      );
      await confirm(tester);

      expect(inRow('d-ana-tablet', find.text('Revoked')), findsOneWidget);
    });

    testWidgets('renames a device of someone else', (tester) async {
      await open(tester);
      await openMenu(tester, 'João - Galaxy');
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('deviceName')),
        'João - Phone',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('saveName')));
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();

      expect(find.text('João - Phone'), findsOneWidget);
    });

    testWidgets('deletes a revoked device', (tester) async {
      await open(tester);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await confirm(tester);

      expect(find.text('Ana - Old phone'), findsNothing);
    });

    testWidgets('a delete of a device that is gone already is quiet', (
      tester,
    ) async {
      await open(tester);
      f.people.devices.removeWhere((d) => d['id'] == 'd-ana-old');

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await confirm(tester);

      expect(find.text('Ana - Old phone'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('an admin\'s device refused by the server is explained', (
      tester,
    ) async {
      await open(tester);
      // The device became an admin's meanwhile (its person was made an admin
      // by the host); the list shows it as it was.
      final device = f.people.devices.firstWhere(
        (d) => d['id'] == 'd-ana-tablet',
      );
      device['admin'] = true;

      await openMenu(tester, 'Ana - Tablet');
      await tester.tap(find.text('Revoke'));
      await tester.pumpAndSettle();
      await confirm(tester);

      expect(
        find.text(
          "That's an admin device. Admin devices are managed on the admin "
          'page.',
        ),
        findsOneWidget,
      );
      // And it is listed as it is now: with no menu.
      expect(find.byTooltip('More actions for Ana - Tablet'), findsNothing);
    });

    testWidgets('Connect a device opens the chooser of who it is for', (
      tester,
    ) async {
      await open(tester);

      await tester.tap(find.text('Connect a device'));
      await f.settle(tester);

      expect(find.text('For'), findsOneWidget);
      expect(find.byType(PairingQr), findsNothing);
    });

    testWidgets('a server older than device management says so', (
      tester,
    ) async {
      f = PeopleFixture('ADMIN');
      f.app.backend.deviceEndpoints = false;
      f.people.failWith = 404;
      await f.start(tester);
      await f.openDevices(tester);

      expect(find.text("This server can't manage devices"), findsOneWidget);
      expect(
        find.text(
          'Update SignalHub on the server, or manage devices on the admin '
          'page.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a server that cannot delete devices says so', (tester) async {
      await open(tester);
      f.people.failWith = 405;

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await confirm(tester);

      expect(
        find.text(
          'This server cannot delete devices. Update SignalHub, or delete it '
          'on the admin page.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the demoted admin keeps nothing of an admin\'s screen', (
      tester,
    ) async {
      await open(tester);
      f.app.backend
        ..userRole = 'MOD'
        ..admin = false;
      f.people.failWith = 403;

      await openMenu(tester, 'João - Galaxy');
      await tester.tap(find.text('Revoke'));
      await tester.pumpAndSettle();
      await confirm(tester);
      f.people.failWith = null;
      await f.settle(tester);

      expect(find.text("Your role changed. You're now a Mod."), findsOneWidget);
      // A mod's own: no one else's.
      expect(find.text('João - Galaxy'), findsNothing);
      expect(find.text('Yours'), findsOneWidget);
    });

    testWidgets('the list failing to read says why and offers Try again', (
      tester,
    ) async {
      f = PeopleFixture('ADMIN');
      await f.start(tester);
      f.people.failWith = 0;
      await f.openDevices(tester);

      expect(find.text("Can't reach the server"), findsOneWidget);

      f.people.failWith = null;
      await tester.tap(find.text('Try again'));
      await f.settle(tester);

      expect(find.text('Ana - Tablet'), findsOneWidget);
    });

    testWidgets('a refresh that fails keeps the older list under a banner', (
      tester,
    ) async {
      await open(tester);
      f.people.failWith = 0;

      await tester.runAsync(f.controller.deviceList.load);
      await f.settle(tester);

      expect(
        find.textContaining("You're offline. Showing the list"),
        findsOneWidget,
      );
      expect(find.text('Ana - Tablet'), findsOneWidget);
    });

    testWidgets('a key the server no longer accepts ends quietly at setup', (
      tester,
    ) async {
      await open(tester);
      f.app.backend.acceptedKey = null;

      await tester.runAsync(f.controller.deviceList.load);
      await f.settle(tester);

      expect(f.controller.phase, ConnectionPhase.disconnected);
      // The screen is closed: setup says why.
      expect(find.byType(DevicesScreen), findsNothing);
      expect(find.text("Can't reach the server"), findsNothing);
    });

    testWidgets('at 360 dp and 200 % text nothing overflows', (tester) async {
      await open(tester, size: const Size(360, 900), textScale: 2);
      f.people.addDevice(
        'd-long',
        'Ana - Kitchen tablet, upstairs, with a very long name indeed',
        'user-2',
        lastActive: f.now,
      );
      await tester.runAsync(f.controller.deviceList.load);
      await f.settle(tester);

      expect(tester.takeException(), isNull);
      await openMenu(
        tester,
        'Ana - Kitchen tablet, upstairs, with a very long name indeed',
      );
      await tester.tap(find.text('Revoke'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // The name is never cut in the question.
      expect(
        find.text(
          'Revoke Ana - Kitchen tablet, upstairs, with a very long name indeed?',
        ),
        findsOneWidget,
      );
      await saveScreenshot(tester, find.byKey(screenshotKey), '3h5');
    });

    testWidgets('the light theme draws the same screen', (tester) async {
      await open(tester, brightness: Brightness.light);

      expect(find.text('Ana - Tablet'), findsOneWidget);
      await saveScreenshot(tester, find.byKey(screenshotKey), '3h-light');
    });
  });
}
