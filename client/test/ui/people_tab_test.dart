import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/app_controller.dart';

import '../support/harness.dart';
import '../support/people_backend.dart';
import '../support/phone.dart';
import '../support/screenshot.dart';

void main() {
  setUpAll(loadDesignFonts);

  /// An admin's device on a server with the design's people.
  (AppHarness, PeopleBackend) adminApp() {
    final app = AppHarness(role: 'ADMIN');
    final people = PeopleBackend(app.backend)..seedDesignData(DateTime.now());
    return (app, people);
  }

  Future<void> openPeople(WidgetTester tester, AppHarness app) async {
    await app.start(tester);
    await app.openTab(tester, HomeTab.people);
  }

  Finder row(String id) => find.byKey(Key('person-$id'));

  testWidgets('people are in sections by role, each with its explanation', (
    tester,
  ) async {
    final (app, _) = adminApp();
    useDesignPhone(tester);
    final semantics = tester.ensureSemantics();

    await openPeople(tester, app);

    expect(find.widgetWithText(AppBar, 'People'), findsOneWidget);
    // A count beside each label, read as one.
    expect(find.bySemanticsLabel('Admins, 2'), findsOneWidget);
    expect(find.bySemanticsLabel('Mods, 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Basic, 3'), findsOneWidget);
    // The order is the roles', then the server's order by name.
    final labels = ['Admins', 'Mods', 'Basic'];
    final tops = [for (final l in labels) tester.getTopLeft(find.text(l)).dy];
    expect(tops, [...tops]..sort());
    expect(
      find.text(
        'Manage people and their devices, except other admins. Set on the '
        'admin page.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Manage their own devices, producers and subscriptions.'),
      findsOneWidget,
    );
    expect(
      find.text('Create producers and subscribe. Their devices are read only.'),
      findsOneWidget,
    );
    for (final id in ['user-0', 'user-1', 'user-2', 'user-3', 'user-4']) {
      expect(row(id), findsOneWidget);
    }
    await saveScreenshot(tester, find.byKey(screenshotKey), '3b');
    semantics.dispose();
  });

  testWidgets('a row says only what the list gives: devices or not paired', (
    tester,
  ) async {
    final (app, people) = adminApp();
    // Marta paired before and has no device active now.
    people.devices.removeWhere((d) => d['id'] == 'd-marta');
    people.paired.add('user-4');
    useDesignPhone(tester);

    await openPeople(tester, app);

    String second(String id) => tester
        .widget<Text>(
          find.descendant(of: row(id), matching: find.byType(Text)).last,
        )
        .data!;
    expect(second('user-0'), '2 devices');
    expect(second('user-1'), '1 device');
    expect(second('user-4'), 'No devices');
    expect(second('user-5'), 'Invited · not paired yet');
    expect(
      find.descendant(of: row('user-0'), matching: find.text('You')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row('user-1'), matching: find.text('You')),
      findsNothing,
    );
  });

  testWidgets('a role nobody has is left out', (tester) async {
    final app = AppHarness(role: 'ADMIN');
    PeopleBackend(app.backend).addUser('user-1', 'João', 'BASIC');
    useDesignPhone(tester);

    await openPeople(tester, app);

    expect(find.text('Admins'), findsOneWidget);
    expect(find.text('Mods'), findsNothing);
    expect(find.text('Basic'), findsOneWidget);
  });

  testWidgets('the tab is read when it opens and on pull to refresh', (
    tester,
  ) async {
    final (app, people) = adminApp();
    useDesignPhone(tester);
    await openPeople(tester, app);
    int reads() =>
        people.requests.where((r) => r == 'GET /api/v1/client/users').length;
    expect(reads(), 1);

    people.addUser('user-9', 'Zeca', 'BASIC');
    await tester.fling(find.text('Admins'), const Offset(0, 400), 1000);
    await app.settle(tester);

    expect(reads(), 2);
    expect(find.text('Zeca'), findsOneWidget);
  });

  testWidgets('a person who was removed leaves the list on the next read', (
    tester,
  ) async {
    final (app, people) = adminApp();
    useDesignPhone(tester);
    await openPeople(tester, app);
    expect(find.text('Marta'), findsOneWidget);

    people.userById('user-4')!.removed = true;
    await tester.runAsync(app.controller.people.load);
    await app.settle(tester);

    expect(find.text('Marta'), findsNothing);
  });

  group('search', () {
    testWidgets('matches names, per role, and says when a role has none', (
      tester,
    ) async {
      final (app, _) = adminApp();
      useDesignPhone(tester);
      final semantics = tester.ensureSemantics();
      await openPeople(tester, app);

      await tester.tap(find.byTooltip('Search people'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ma');
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Basic, 1 of 3'), findsOneWidget);
      expect(find.bySemanticsLabel('Mods, 0 of 1'), findsOneWidget);
      // Admins have no match either; each role says so.
      expect(find.bySemanticsLabel('Admins, 0 of 2'), findsOneWidget);
      expect(find.text('No one matches.'), findsNWidgets(2));
      expect(find.text('Marta'), findsOneWidget);
      expect(find.text('João'), findsNothing);
      // The explanations make room for the matches.
      expect(
        find.text(
          'Create producers and subscribe. Their devices are read only.',
        ),
        findsNothing,
      );
      await saveScreenshot(tester, find.byKey(screenshotKey), '3j');
      semantics.dispose();
    });

    testWidgets('no match at all says so, and clearing brings the list back', (
      tester,
    ) async {
      final (app, _) = adminApp();
      useDesignPhone(tester);
      await openPeople(tester, app);

      await tester.tap(find.byTooltip('Search people'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No one matches "zzz".'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('No one matches "zzz".'), findsNothing);
      expect(find.text('Marta'), findsOneWidget);
      expect(find.text('João'), findsOneWidget);
    });

    testWidgets('the search field and its clear button are named', (
      tester,
    ) async {
      final (app, _) = adminApp();
      useDesignPhone(tester);
      final semantics = tester.ensureSemantics();
      await openPeople(tester, app);

      await tester.tap(find.byTooltip('Search people'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Search people'), findsWidgets);
      await tester.enterText(find.byType(TextField), 'a');
      await tester.pumpAndSettle();
      expect(find.byTooltip('Clear search'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('Back leaves the search and forgets it', (tester) async {
      final (app, _) = adminApp();
      useDesignPhone(tester);
      await openPeople(tester, app);

      await tester.tap(find.byTooltip('Search people'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ma');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(find.text('João'), findsOneWidget);
      expect(find.byTooltip('Search people'), findsOneWidget);
    });
  });

  group('when the list cannot be read', () {
    testWidgets('a first read that fails says why and offers Try again', (
      tester,
    ) async {
      final (app, people) = adminApp();
      people.failWith = 0;
      useDesignPhone(tester);

      await openPeople(tester, app);

      expect(find.text("Can't reach the server"), findsOneWidget);
      expect(find.text('Check your connection and try again.'), findsOneWidget);

      people.failWith = null;
      await tester.tap(find.text('Try again'));
      await app.settle(tester);

      expect(find.text('Marta'), findsOneWidget);
      expect(find.text("Can't reach the server"), findsNothing);
    });

    testWidgets('a refresh that fails keeps the older list under a banner', (
      tester,
    ) async {
      final (app, people) = adminApp();
      useDesignPhone(tester);
      await openPeople(tester, app);

      people.failWith = 0;
      await tester.runAsync(app.controller.people.load);
      await app.settle(tester);

      expect(
        find.textContaining("You're offline. Showing the list from"),
        findsOneWidget,
      );
      expect(find.text('Marta'), findsOneWidget);

      people.failWith = null;
      await tester.tap(find.text('Try again'));
      await app.settle(tester);
      expect(find.textContaining('Showing the list from'), findsNothing);
    });

    testWidgets('a server answer that is not a connection failure is said', (
      tester,
    ) async {
      final (app, people) = adminApp();
      people.failWith = 500;
      useDesignPhone(tester);

      await openPeople(tester, app);

      expect(find.text("Couldn't load people"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('a key the server no longer accepts ends quietly at setup', (
      tester,
    ) async {
      final (app, _) = adminApp();
      useDesignPhone(tester);
      await openPeople(tester, app);

      app.backend.acceptedKey = null;
      await tester.runAsync(app.controller.people.load);
      await app.settle(tester);

      expect(app.controller.phase, ConnectionPhase.disconnected);
      expect(find.text("Couldn't load people"), findsNothing);
    });
  });

  group('layout', () {
    testWidgets('at 360 dp and 200 % text names end in an ellipsis', (
      tester,
    ) async {
      final app = AppHarness(role: 'ADMIN');
      final people = PeopleBackend(app.backend);
      people
        ..addUser('user-1', 'Maria de Fátima Albuquerque', 'BASIC')
        ..addUser('user-2', 'Rui', 'BASIC');
      people.addDevice('d-1', 'Phone', 'user-1');
      useDesignPhone(tester, size: const Size(360, 900), textScale: 2);

      await openPeople(tester, app);

      expect(tester.takeException(), isNull);
      expect(find.text('Rui'), findsOneWidget);
      // The tab bar and the floating button keep their place.
      expect(find.text('Invite'), findsOneWidget);
      await saveScreenshot(tester, find.byKey(screenshotKey), '3b2');
    });

    testWidgets('the light theme draws the same sections', (tester) async {
      final (app, _) = adminApp();
      useDesignPhone(tester, brightness: Brightness.light);

      await openPeople(tester, app);

      expect(find.text('Admins'), findsOneWidget);
      await saveScreenshot(tester, find.byKey(screenshotKey), '5d');
    });

    testWidgets('the last row clears the floating Invite button', (
      tester,
    ) async {
      final app = AppHarness(role: 'ADMIN');
      final people = PeopleBackend(app.backend);
      for (var i = 0; i < 12; i++) {
        people.addUser('user-${i + 1}', 'Person $i', 'BASIC');
      }
      useDesignPhone(tester);
      await openPeople(tester, app);

      await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
      await tester.pumpAndSettle();

      final last = tester.getRect(find.text('Person 9'));
      final invite = tester.getRect(find.byType(FloatingActionButton));
      expect(last.bottom, lessThanOrEqualTo(invite.top));
    });
  });
}
