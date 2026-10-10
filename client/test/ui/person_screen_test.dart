import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/app_controller.dart';
import 'package:signalhub_client/src/models/users.dart';

import '../support/people_fixture.dart';
import '../support/screenshot.dart';

void main() {
  setUpAll(loadDesignFonts);

  late PeopleFixture f;

  Future<void> open(
    WidgetTester tester,
    String id, {
    Size size = const Size(412, 892),
    double textScale = 1,
    Brightness brightness = Brightness.dark,
    void Function(PeopleFixture)? setUp,
  }) async {
    f = PeopleFixture('ADMIN');
    f.people.producers['user-2'] = [
      {
        'id': 'p-1',
        'name': 'ana-reports',
        'visibility': 'PUBLIC',
        'disabled': false,
      },
      {
        'id': 'p-2',
        'name': 'garage-door',
        'visibility': 'PRIVATE',
        'disabled': true,
      },
    ];
    setUp?.call(f);
    await f.start(
      tester,
      size: size,
      textScale: textScale,
      brightness: brightness,
    );
    await f.app.openTab(tester, HomeTab.people);
    await tester.tap(find.byKey(Key('person-$id')));
    await f.settle(tester);
  }

  Finder row(String id) => find.byKey(Key('device-$id'));

  List<String> words(String id) => [
    for (final text
        in find
            .descendant(of: row(id), matching: find.byType(Text))
            .evaluate()
            .map((e) => (e.widget as Text).data))
      ?text,
  ];

  SegmentedButton<Object?> segments(WidgetTester tester) =>
      tester.widget(find.byKey(const Key('role')));

  Future<void> choose(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('role')),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('confirm')));
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
  }

  group('a person, as an admin sees them', () {
    testWidgets('shows their role, devices and producers', (tester) async {
      final semantics = tester.ensureSemantics();
      await open(tester, 'user-2');

      expect(find.widgetWithText(AppBar, 'Ana'), findsOneWidget);
      expect(find.text('Role'), findsOneWidget);
      expect(find.text('Devices'), findsOneWidget);
      expect(find.text('Producers'), findsOneWidget);
      expect(
        find.text(
          'Admin is set on the admin page, on the computer running SignalHub.',
        ),
        findsOneWidget,
      );
      // The role: Mod, with Admin shown and not available.
      expect(segments(tester).selected, {UserRole.mod});
      expect(find.text('Admin'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Admin, not available. Set on the admin page'),
        findsOneWidget,
      );
      // Their devices, each with Revoke named for it; a revoked one is greyed.
      expect(words('d-ana-pixel'), [
        'Ana - Pixel',
        'Last active today',
        'Revoke',
      ]);
      expect(words('d-ana-tablet'), [
        'Ana - Tablet',
        'Last active 3 days ago',
        'Revoke',
      ]);
      expect(words('d-ana-old'), [
        'Ana - Old phone',
        'Revoked',
        'Revoked 4 Oct',
        'Delete',
      ]);
      expect(find.bySemanticsLabel('Revoke Ana - Pixel'), findsOneWidget);
      expect(find.text('Pair a device for Ana'), findsOneWidget);
      // Nobody else's devices.
      expect(find.text('Sofia - Pixel'), findsNothing);
      // Their producers, as the per-person call lists them.
      expect(find.text('ana-reports'), findsOneWidget);
      expect(find.text('Public'), findsOneWidget);
      expect(find.text('garage-door'), findsOneWidget);
      expect(find.text('Private · Disabled'), findsOneWidget);
      await saveScreenshot(tester, find.byKey(screenshotKey), '3e');
      semantics.dispose();
    });

    testWidgets('an empty list of producers says so by name', (tester) async {
      await open(tester, 'user-3');

      expect(find.text('João has no producers.'), findsOneWidget);
      expect(
        f.people.requests,
        contains('GET /api/v1/client/users/user-3/producers'),
      );
    });

    testWidgets(
      'a person who never paired has no devices yet and can be paired for',
      (tester) async {
        await open(tester, 'user-5');

        expect(find.text('Pair a device for Rui'), findsOneWidget);
        expect(find.text('Revoke'), findsNothing);
      },
    );

    testWidgets('changing the role asks first, in the primary colour', (
      tester,
    ) async {
      await open(tester, 'user-2');

      await choose(tester, 'Basic');

      expect(find.text('Make Ana a Basic user?'), findsOneWidget);
      expect(
        find.text(
          'Ana will no longer be able to connect, rename or revoke devices. '
          'Their producers and subscriptions stay. It applies on their next '
          'action.',
        ),
        findsOneWidget,
      );
      // Someone else is affected but a role can be changed back: primary.
      final action = tester.widget<TextButton>(
        find.byKey(const Key('confirm')),
      );
      expect(action.style?.foregroundColor, isNull);
      expect(find.text('Make Basic'), findsOneWidget);
      expect(f.people.requests.where((r) => r.startsWith('PATCH')), isEmpty);
      await saveScreenshot(tester, find.byKey(screenshotKey), '3e3');

      await confirm(tester);

      final patch = f.app.backend.requests.lastWhere(
        (r) => r.method == 'PATCH',
      );
      expect(patch.url.path, endsWith('/users/user-2'));
      expect(jsonDecode(patch.body), {'role': 'BASIC'});
      expect(segments(tester).selected, {UserRole.basic});
      expect(f.people.userById('user-2')!.role, 'BASIC');
    });

    testWidgets('making someone a Mod says what they can then do', (
      tester,
    ) async {
      await open(tester, 'user-3');

      await choose(tester, 'Mod');

      expect(find.text('Make João a Mod?'), findsOneWidget);
      expect(
        find.text(
          'João will be able to connect, rename, revoke and delete their own '
          'devices.',
        ),
        findsOneWidget,
      );
      await confirm(tester);

      expect(segments(tester).selected, {UserRole.mod});
    });

    testWidgets('Cancel changes nothing', (tester) async {
      await open(tester, 'user-2');
      await choose(tester, 'Basic');

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(f.people.requests.where((r) => r.startsWith('PATCH')), isEmpty);
      expect(segments(tester).selected, {UserRole.mod});
    });

    testWidgets('choosing the role they have asks nothing', (tester) async {
      await open(tester, 'user-2');

      await choose(tester, 'Mod');

      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('a person removed meanwhile is said, in a message', (
      tester,
    ) async {
      await open(tester, 'user-4');
      f.people.userById('user-4')!.removed = true;

      await choose(tester, 'Mod');
      await confirm(tester);

      expect(
        find.text("Marta's access was removed, so their role can't change."),
        findsOneWidget,
      );
      // The page they were on stays; People forgets them on the next read.
      expect(find.widgetWithText(AppBar, 'Marta'), findsOneWidget);
      await saveScreenshot(tester, find.byKey(screenshotKey), '3e4');
    });

    testWidgets('someone made an admin meanwhile is said, in a message', (
      tester,
    ) async {
      await open(tester, 'user-4');
      f.people.userById('user-4')!.role = 'ADMIN';

      await choose(tester, 'Mod');
      await confirm(tester);

      expect(
        find.text('Marta is an admin. Admins are managed on the admin page.'),
        findsOneWidget,
      );
    });

    testWidgets('no connection is said, with Retry', (tester) async {
      await open(tester, 'user-2');
      await choose(tester, 'Basic');
      f.people.failWith = 0;
      await tester.tap(find.byKey(const Key('confirm')));
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();

      expect(
        find.text(
          "Couldn't change the role. Check your connection and try again.",
        ),
        findsOneWidget,
      );
      expect(segments(tester).selected, {UserRole.mod});

      f.people.failWith = null;
      await tester.tap(find.text('Retry'));
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();

      expect(segments(tester).selected, {UserRole.basic});
    });

    testWidgets('a role taken away is said once, and the page follows it', (
      tester,
    ) async {
      await open(tester, 'user-2');
      f.app.backend
        ..userRole = 'MOD'
        ..admin = false;

      await choose(tester, 'Basic');
      await confirm(tester);
      await f.settle(tester);

      expect(find.text("Your role changed. You're now a Mod."), findsOneWidget);
      expect(
        find.text('This screen is not available to your role'),
        findsOneWidget,
      );
      expect(f.people.userById('user-2')!.role, 'MOD');
    });

    testWidgets('revokes a device after asking, naming the person', (
      tester,
    ) async {
      await open(tester, 'user-2');

      await tester.tap(find.text('Revoke').first);
      await tester.pumpAndSettle();

      expect(find.text('Revoke Ana - Pixel?'), findsOneWidget);
      expect(
        find.text(
          "It stops getting events at once and can't be used again. To use "
          "it again, Ana has to connect it with a new code. Ana's other "
          'devices and the admins are told.',
        ),
        findsOneWidget,
      );
      await confirm(tester);

      expect(words('d-ana-pixel'), [
        'Ana - Pixel',
        'Revoked',
        'Revoked 10 Oct',
        'Delete',
      ]);
    });

    testWidgets('deletes a revoked device after asking', (tester) async {
      await open(tester, 'user-2');

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await confirm(tester);

      expect(find.text('Ana - Old phone'), findsNothing);
    });

    testWidgets('Pair a device for Ana goes straight to her name step', (
      tester,
    ) async {
      await open(tester, 'user-2');

      await tester.tap(find.byKey(const Key('pairForPerson')));
      await f.settle(tester);

      expect(find.text('Connect a device'), findsOneWidget);
      expect(find.text('For Ana.'), findsOneWidget);
      // No chooser: the person is fixed.
      expect(find.text('For'), findsNothing);

      await tester.enterText(
        find.byKey(const Key('pairingName')),
        'Ana - Laptop',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('showCode')));
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
      await tester.pump();

      final body = jsonDecode(
        f.app.backend.requests
            .lastWhere(
              (r) =>
                  r.method == 'POST' && r.url.path.endsWith('/client/pairings'),
            )
            .body,
      );
      expect(body, {'name': 'Ana - Laptop', 'userId': 'user-2'});
      expect(
        find.text(
          "Whoever uses this code gets a device of Ana's. Share it only with "
          'Ana.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('producers that cannot be read say so, with Try again', (
      tester,
    ) async {
      await open(
        tester,
        'user-2',
        setUp: (f) => f.people.producersFailWith = 0,
      );

      expect(find.text("Couldn't load Ana's producers."), findsOneWidget);
      // The rest of the page is there.
      expect(find.text('Ana - Pixel'), findsOneWidget);

      f.people.producersFailWith = null;
      await tester.tap(find.text('Try again'));
      await f.settle(tester);

      expect(find.text('ana-reports'), findsOneWidget);
      expect(find.text("Couldn't load Ana's producers."), findsNothing);
    });

    testWidgets(
      'pull to refresh reads the person, devices and producers again',
      (tester) async {
        await open(tester, 'user-2');
        int reads(String path) =>
            f.people.requests.where((r) => r == 'GET $path').length;
        final before = reads('/api/v1/client/users/user-2/producers');

        f.people.producers['user-2']!.add({
          'id': 'p-3',
          'name': 'nas',
          'visibility': 'PRIVATE',
          'disabled': false,
        });
        await tester.fling(find.text('Role'), const Offset(0, 400), 1000);
        await f.settle(tester);

        expect(reads('/api/v1/client/users/user-2/producers'), before + 1);
        expect(find.text('nas'), findsOneWidget);
      },
    );
  });

  group('a person who was removed', () {
    testWidgets('a page opened on them says so, whatever the server answered', (
      tester,
    ) async {
      f = PeopleFixture('ADMIN');
      await f.start(tester);
      await f.app.openTab(tester, HomeTab.people);
      f.people.userById('user-4')!.removed = true;

      await tester.tap(find.byKey(const Key('person-user-4')));
      await f.settle(tester);

      expect(find.text('This person was removed'), findsOneWidget);
      expect(
        find.text(
          'They no longer have access to this server, so there is nothing to '
          'change.',
        ),
        findsOneWidget,
      );
      expect(find.text('Back to People'), findsOneWidget);
      expect(find.byKey(const Key('role')), findsNothing);
      await saveScreenshot(tester, find.byKey(screenshotKey), '3e5');

      await tester.tap(find.text('Back to People'));
      await f.settle(tester);

      // The list no longer has them.
      expect(find.widgetWithText(AppBar, 'People'), findsOneWidget);
      expect(find.byKey(const Key('person-user-4')), findsNothing);
    });
  });

  group('another admin, and your own page', () {
    testWidgets('is read only: nothing on it is a control', (tester) async {
      await open(tester, 'user-1');

      expect(find.widgetWithText(AppBar, 'Sofia'), findsOneWidget);
      expect(segments(tester).selected, {UserRole.admin});
      expect(segments(tester).onSelectionChanged, isNull);
      expect(
        find.text(
          'Admins are managed on the admin page, on the computer running '
          'SignalHub.',
        ),
        findsOneWidget,
      );
      expect(words('d-sofia'), [
        'Sofia - Pixel',
        'Admin device',
        'Last active today',
      ]);
      expect(
        find.text(
          "An admin's devices can't be renamed or revoked from the app.",
        ),
        findsOneWidget,
      );
      expect(find.text('Revoke'), findsNothing);
      expect(find.text('Delete'), findsNothing);
      expect(find.textContaining('Pair a device'), findsNothing);
      expect(find.text('Sofia has no producers.'), findsOneWidget);
      await saveScreenshot(tester, find.byKey(screenshotKey), '3e2');
    });

    testWidgets('your own page looks the same, with a You tag', (tester) async {
      await open(tester, 'user-0');

      expect(find.widgetWithText(AppBar, 'Rodrigo'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('You')),
        findsOneWidget,
      );
      expect(segments(tester).onSelectionChanged, isNull);
      expect(words('d-tablet'), [
        'Rodrigo - Tablet',
        'Admin device',
        'Last active today',
      ]);
      expect(find.text('Revoke'), findsNothing);
      expect(find.textContaining('Pair a device'), findsNothing);
      expect(find.text('Rodrigo has no producers.'), findsOneWidget);
    });
  });

  group('layout', () {
    testWidgets('at 360 dp and 200 % text nothing overflows', (tester) async {
      await open(
        tester,
        'user-2',
        size: const Size(360, 900),
        textScale: 2,
        setUp: (f) {
          f.people.addDevice(
            'd-long',
            'Ana - Kitchen tablet, upstairs, with a very long name indeed',
            'user-2',
            lastActive: f.now,
          );
        },
      );

      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('garage-door'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the light theme draws the same page', (tester) async {
      await open(tester, 'user-2', brightness: Brightness.light);

      expect(find.text('Ana'), findsWidgets);
      await saveScreenshot(tester, find.byKey(screenshotKey), '3e-light');
    });
  });
}
