import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/app_controller.dart';
import 'package:signalhub_client/src/ui/sign_in_browser_screen.dart';

import '../support/fakes.dart';
import '../support/first_run_support.dart';
import '../support/people_fixture.dart';
import '../support/phone.dart';
import '../support/screenshot.dart';
import '../support/web_sign_in_backend.dart';

void main() {
  setUpAll(loadDesignFonts);

  late PeopleFixture f;
  late WebSignInBackend page;
  late FakeCamera camera;
  late FakeIncomingLinks links;

  Finder byKey(String key) => find.byKey(Key(key));

  /// The link of the page's QR code, for the server this app is connected to
  /// unless [server] says another.
  String linkOf({String server = serverUrl, String? code}) => Uri(
    scheme: 'signalhub',
    host: 'signin',
    queryParameters: {
      'server': server,
      'code': code ?? WebSignInBackend.scanCode,
    },
  ).toString();

  /// A device of [role] with a page waiting to sign a browser in.
  Future<void> start(
    WidgetTester tester, {
    String role = 'BASIC',
    String? initialLink,
  }) async {
    f = PeopleFixture(role);
    page = WebSignInBackend(f.app.backend)..add();
    camera = FakeCamera();
    links = FakeIncomingLinks(initialLink);
    f.app
      ..signInScanner = camera.build
      ..incomingLinks = links;
    await f.start(tester);
  }

  Future<void> openScanner(WidgetTester tester) async {
    await f.app.openTab(tester, HomeTab.settings);
    await tester.tap(byKey('signInBrowser'));
    await f.settle(tester);
  }

  Future<void> scan(WidgetTester tester, [String? code]) async {
    camera.scan(code ?? linkOf());
    await f.settle(tester);
  }

  Future<void> typeCode(WidgetTester tester, String typed) async {
    await tester.tap(byKey('typeCode'));
    await tester.pumpAndSettle();
    await tester.enterText(byKey('signInCode'), typed);
    await tester.pump();
  }

  Future<void> tapContinue(WidgetTester tester) async {
    await tester.tap(byKey('continueCode'));
    await f.settle(tester);
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await f.settle(tester);
  }

  Future<void> shot(WidgetTester tester, String name) =>
      saveScreenshot(tester, byKey('screenshot'), name);

  group('the Settings row', () {
    for (final role in ['BASIC', 'MOD', 'ADMIN']) {
      testWidgets('3p: a $role has it, and it opens the scanner', (
        tester,
      ) async {
        await start(tester, role: role);
        await f.app.openTab(tester, HomeTab.settings);

        // Beside Devices, between it and About this server, for every role.
        double top(String text) => tester.getTopLeft(find.text(text)).dy;
        expect(top('Sign in a browser'), greaterThan(top('Devices')));
        expect(top('Sign in a browser'), lessThan(top('About this server')));
        expect(find.text('Scan the code a web page shows'), findsOneWidget);
        expect(find.byIcon(Icons.qr_code_scanner), findsOneWidget);
        if (role == 'BASIC') await shot(tester, '3p');

        await tester.tap(byKey('signInBrowser'));
        await f.settle(tester);

        expect(find.byType(SignInBrowserScreen), findsOneWidget);
        expect(
          find.widgetWithText(AppBar, 'Sign in a browser'),
          findsOneWidget,
        );
        expect(find.byTooltip('Close'), findsOneWidget);
        expect(camera.builds, greaterThan(0));
        expect(
          find.text('Point the camera at the code on the page.'),
          findsOneWidget,
        );
        expect(find.text('Type a code'), findsOneWidget);
        // Nothing is signed in by opening it.
        expect(page.requests, isEmpty);
      });
    }

    testWidgets('is not inside Devices', (tester) async {
      await start(tester);
      await openScanner(tester);

      await tester.tap(find.byTooltip('Close'));
      await f.settle(tester);
      await tester.tap(byKey('devices'));
      await f.settle(tester);

      expect(find.text('Sign in a browser'), findsNothing);
    });
  });

  group('scanning the page\'s code', () {
    testWidgets('the sheet\'s buttons clear the navigation bar', (
      tester,
    ) async {
      await start(tester);
      useEdgeToEdgePhone(tester);
      await openScanner(tester);

      await scan(tester);

      expect(find.text('Sign in this browser?'), findsOneWidget);
      expectClearOfNavigationBar(tester, byKey('approveSignIn'));
      expectClearOfNavigationBar(tester, byKey('cancelSignIn'));
    });

    testWidgets('6a3: asks Sign in this browser? and signs it in', (
      tester,
    ) async {
      await start(tester);
      await openScanner(tester);
      await shot(tester, '6a3-camera');

      await scan(tester);

      expect(find.text('Sign in this browser?'), findsOneWidget);
      expect(find.text('Firefox on Linux'), findsOneWidget);
      expect(find.text('Asked just now'), findsOneWidget);
      expect(find.byIcon(Icons.language), findsOneWidget);
      expect(
        find.text(
          'Only sign in a browser you are looking at right now. It can read '
          'and send what you can for 30 days, or until you sign it out.',
        ),
        findsOneWidget,
      );
      expect(page.lookups, [WebSignInBackend.scanCode]);
      // Scanning alone never signs anyone in.
      expect(page.approved, isEmpty);
      await shot(tester, '6a3');

      await tapAndSettle(tester, byKey('approveSignIn'));

      expect(page.approved, ['signin-1']);
      expect(find.text('Sign in this browser?'), findsNothing);
      expect(find.text('Browser signed in'), findsOneWidget);
      expect(
        find.text(
          'Firefox on Linux can now use your SignalHub for 30 days. You can '
          'sign it out any time in Devices.',
        ),
        findsOneWidget,
      );
      await shot(tester, '6a4-app');
    });

    testWidgets('the browser is a device once signed in, and Done closes', (
      tester,
    ) async {
      await start(tester);
      await openScanner(tester);
      int reads() => f.people.requests
          .where((r) => r == 'GET /api/v1/client/devices')
          .length;
      final before = reads();
      await scan(tester);
      await tapAndSettle(tester, byKey('approveSignIn'));

      expect(reads(), greaterThan(before));

      await tapAndSettle(tester, byKey('signInDone'));

      expect(find.byType(SignInBrowserScreen), findsNothing);
      expect(find.text('Sign in a browser'), findsOneWidget);
    });

    testWidgets('Cancel tells the page and goes back to the camera', (
      tester,
    ) async {
      await start(tester);
      await openScanner(tester);
      await scan(tester);

      await tapAndSettle(tester, byKey('cancelSignIn'));

      expect(page.cancelled, ['signin-1']);
      expect(page.approved, isEmpty);
      expect(find.text('Sign in this browser?'), findsNothing);
      expect(find.byType(SignInBrowserScreen), findsOneWidget);
      expect(find.text('Browser signed in'), findsNothing);
      // The camera still sees the code that was cancelled: no new question.
      await scan(tester);
      expect(page.lookups, hasLength(1));
      expect(find.text('Sign in this browser?'), findsNothing);
    });

    testWidgets('dismissing the sheet is a cancel too', (tester) async {
      await start(tester);
      await openScanner(tester);
      await scan(tester);

      await tester.tapAt(const Offset(200, 100));
      await f.settle(tester);

      expect(find.text('Sign in this browser?'), findsNothing);
      expect(page.cancelled, ['signin-1']);
    });

    testWidgets('a code that is not a sign-in code says so', (tester) async {
      await start(tester);
      await openScanner(tester);

      await scan(tester, pairingUri);

      expect(
        find.text(
          "That isn't a sign-in code from a SignalHub page. Scan the code a "
          'web page shows.',
        ),
        findsOneWidget,
      );
      expect(page.requests, isEmpty);
    });

    testWidgets('a code of another server is refused, naming this one', (
      tester,
    ) async {
      await start(tester);
      await openScanner(tester);

      await scan(tester, linkOf(server: 'https://other.test'));

      expect(
        find.text(
          'That code is for another server. This app is connected to '
          'signalhub.test.',
        ),
        findsOneWidget,
      );
      expect(page.requests, isEmpty);
      expect(find.text('Sign in this browser?'), findsNothing);
    });

    testWidgets('a page that is gone says the sign-in ended', (tester) async {
      await start(tester);
      await openScanner(tester);
      await scan(tester);
      page.expire();

      await tapAndSettle(tester, byKey('approveSignIn'));

      expect(find.text('Sign in this browser?'), findsNothing);
      expect(
        find.text(
          'That sign-in has ended. Show a new code on the page and scan it.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('no answer from the server is a banner with Try again', (
      tester,
    ) async {
      await start(tester);
      await openScanner(tester);
      f.app.backend.offline = true;

      await scan(tester);

      expect(
        find.text(
          "Can't reach SignalHub. Check your connection and try again.",
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
      await shot(tester, '6e-app-offline');

      f.app.backend.offline = false;
      await tapAndSettle(tester, find.text('Try again'));

      expect(find.text('Sign in this browser?'), findsOneWidget);
      expect(find.byKey(const Key('signInFailure')), findsNothing);
    });

    testWidgets('an approval that cannot reach the server stays on the sheet', (
      tester,
    ) async {
      await start(tester);
      await openScanner(tester);
      await scan(tester);
      page.approveFailsWith = 0;

      await tapAndSettle(tester, byKey('approveSignIn'));

      expect(find.text('Sign in this browser?'), findsOneWidget);
      expect(
        tester.widget<Text>(byKey('signInSheetFailure')).data,
        "Can't reach SignalHub. Check your connection and try again.",
      );

      page.approveFailsWith = null;
      await tapAndSettle(tester, byKey('approveSignIn'));

      expect(find.text('Browser signed in'), findsOneWidget);
    });

    testWidgets('a camera that is not allowed leaves the typed code', (
      tester,
    ) async {
      await start(tester);
      await openScanner(tester);

      camera.deny();
      await f.settle(tester);

      expect(find.byKey(const Key('cameraOff')), findsOneWidget);
      expect(find.textContaining("can't use the camera"), findsOneWidget);
      expect(find.text('Type a code'), findsOneWidget);
    });
  });

  group('typing the code', () {
    testWidgets('6d: Continue waits for a code, then asks the same question', (
      tester,
    ) async {
      await start(tester);
      await openScanner(tester);

      await typeCode(tester, '');

      expect(find.text('Enter the code the page shows.'), findsOneWidget);
      expect(find.text('Code'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.enterText(byKey('signInCode'), 'K7Q-4');
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );

      await tester.enterText(byKey('signInCode'), 'K7Q-4MX');
      await tester.pump();
      await shot(tester, '6d-code');
      await tapContinue(tester);

      expect(page.lookups, ['K7Q-4MX']);
      expect(find.text('Sign in this browser?'), findsOneWidget);
      expect(find.text('Firefox on Linux'), findsOneWidget);

      await tapAndSettle(tester, byKey('approveSignIn'));

      expect(page.approved, ['signin-1']);
      expect(find.text('Browser signed in'), findsOneWidget);
    });

    testWidgets('6d: a wrong code says so under the field and keeps it', (
      tester,
    ) async {
      await start(tester);
      await openScanner(tester);

      await typeCode(tester, 'K7Q-4MY');
      await tapContinue(tester);

      expect(
        find.text(
          "That code isn't right or has run out. Check the page and try "
          'again.',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.error), findsOneWidget);
      expect(find.text('K7Q-4MY'), findsOneWidget);
      expect(find.text('Sign in this browser?'), findsNothing);
      await shot(tester, '6d-wrong');

      // Typing again takes the message away, and the right code goes on.
      await tester.enterText(byKey('signInCode'), 'K7Q-4MX');
      await tester.pump();
      expect(find.textContaining("isn't right"), findsNothing);
      await tapContinue(tester);
      expect(find.text('Sign in this browser?'), findsOneWidget);
    });

    testWidgets('6e: too many wrong tries are refused for a while', (
      tester,
    ) async {
      await start(tester);
      await openScanner(tester);
      await tester.tap(byKey('typeCode'));
      await tester.pumpAndSettle();

      for (var i = 0; i < WebSignInBackend.triesAllowed; i++) {
        await tester.enterText(byKey('signInCode'), 'K7Q-4M${'ABCDE'[i]}');
        await tester.pump();
        await tapContinue(tester);
      }
      await tester.enterText(byKey('signInCode'), 'K7Q-4MX');
      await tester.pump();
      await tapContinue(tester);

      expect(
        find.text('Too many tries. Wait a few minutes, then try again.'),
        findsOneWidget,
      );
      expect(find.text('Sign in this browser?'), findsNothing);
      await shot(tester, '6e-app-too-many');
    });

    testWidgets('a code that cannot be one is not sent', (tester) async {
      await start(tester);
      await openScanner(tester);

      // Zero and one are not in the codes: a typo, not a try.
      await typeCode(tester, 'K7Q-4M0');
      await tapContinue(tester);

      expect(page.lookups, isEmpty);
      expect(page.wrongTries, 0);
      expect(find.textContaining("isn't right"), findsOneWidget);
    });

    testWidgets('no answer from the server is a banner above the field', (
      tester,
    ) async {
      await start(tester);
      await openScanner(tester);
      f.app.backend.offline = true;

      await typeCode(tester, 'K7Q-4MX');
      await tapContinue(tester);

      expect(find.textContaining("Can't reach SignalHub"), findsOneWidget);
      expect(find.text('K7Q-4MX'), findsOneWidget);

      f.app.backend.offline = false;
      await tapAndSettle(tester, find.text('Try again'));

      expect(find.text('Sign in this browser?'), findsOneWidget);
    });

    testWidgets('Back from the code goes back to the camera', (tester) async {
      await start(tester);
      await openScanner(tester);
      await tester.tap(byKey('typeCode'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(SignInBrowserScreen), findsOneWidget);
      expect(find.text('Type a code'), findsOneWidget);
      expect(find.text('Enter the code the page shows.'), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(SignInBrowserScreen), findsNothing);
    });
  });

  group('a link the phone opens', () {
    testWidgets('goes straight to the question, with no camera', (
      tester,
    ) async {
      await start(tester, initialLink: linkOf());
      await f.settle(tester);

      expect(find.byType(SignInBrowserScreen), findsOneWidget);
      expect(find.text('Sign in this browser?'), findsOneWidget);
      expect(find.text('Firefox on Linux'), findsOneWidget);
      expect(page.lookups, [WebSignInBackend.scanCode]);
      expect(camera.builds, 0);

      await tapAndSettle(tester, byKey('approveSignIn'));

      expect(page.approved, ['signin-1']);
      expect(find.text('Browser signed in'), findsOneWidget);
    });

    testWidgets('opened while the app runs does the same', (tester) async {
      await start(tester);
      expect(find.byType(SignInBrowserScreen), findsNothing);

      links.open(linkOf());
      await f.settle(tester);

      expect(find.text('Sign in this browser?'), findsOneWidget);
      expect(camera.builds, 0);
    });

    testWidgets('is cancelled like a scanned one, and then the camera shows', (
      tester,
    ) async {
      await start(tester);
      links.open(linkOf());
      await f.settle(tester);

      await tapAndSettle(tester, byKey('cancelSignIn'));

      expect(page.cancelled, ['signin-1']);
      expect(
        find.text('Point the camera at the code on the page.'),
        findsOneWidget,
      );
      expect(camera.builds, greaterThan(0));
    });

    testWidgets('of another server is refused, naming this one', (
      tester,
    ) async {
      await start(tester);

      links.open(linkOf(server: 'https://other.test'));
      await f.settle(tester);

      expect(find.byType(SignInBrowserScreen), findsOneWidget);
      expect(
        find.text(
          'That code is for another server. This app is connected to '
          'signalhub.test.',
        ),
        findsOneWidget,
      );
      expect(page.requests, isEmpty);
    });

    testWidgets('a newer link replaces the screen of an older one', (
      tester,
    ) async {
      await start(tester);
      links.open(linkOf());
      await f.settle(tester);
      await tapAndSettle(tester, byKey('cancelSignIn'));
      page.add(id: 'signin-2', codes: ['shsc1_second']);

      links.open(linkOf(code: 'shsc1_second'));
      await f.settle(tester);

      expect(find.byType(SignInBrowserScreen), findsOneWidget);
      expect(find.text('Sign in this browser?'), findsOneWidget);
      await tapAndSettle(tester, byKey('approveSignIn'));
      expect(page.approved, ['signin-2']);
    });

    testWidgets('that is not a sign-in link is ignored', (tester) async {
      await start(tester);

      links.open(pairingUri);
      links.open('https://signalhub.test/');
      await f.settle(tester);

      expect(find.byType(SignInBrowserScreen), findsNothing);
      expect(page.requests, isEmpty);
    });

    testWidgets('does nothing for an app that is not set up', (tester) async {
      f = PeopleFixture('BASIC');
      page = WebSignInBackend(f.app.backend)..add();
      camera = FakeCamera();
      links = FakeIncomingLinks(linkOf());
      f.app
        ..signInScanner = camera.build
        ..incomingLinks = links;
      await f.app.start(tester, connected: false);

      expect(find.byType(SignInBrowserScreen), findsNothing);
      expect(page.requests, isEmpty);
      expect(f.controller.phase, ConnectionPhase.disconnected);
    });
  });
}
