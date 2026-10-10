import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/api/signalhub_api.dart';
import 'package:signalhub_client/src/app_controller.dart';
import 'package:signalhub_client/src/connection/setup_failure.dart';

import '../support/fakes.dart';
import '../support/first_run_support.dart';
import '../support/phone.dart';
import '../support/screenshot.dart';

void main() {
  setUpAll(loadDesignFonts);

  Finder byKey(String key) => find.byKey(Key(key));

  Future<FirstRunHarness> setup(
    WidgetTester tester, {
    bool withCode = true,
  }) async {
    final app = FirstRunHarness();
    if (withCode) app.backend.pairingCodes.add(pairingCode);
    useDesignPhone(tester);
    await app.start(tester, connected: false);
    return app;
  }

  Future<void> shot(WidgetTester tester, String name) =>
      saveScreenshot(tester, byKey('screenshot'), name);

  group('the first screen', () {
    testWidgets('4a: scans the invitation, or pastes its link', (tester) async {
      await setup(tester);

      expect(find.text('Connect to SignalHub'), findsOneWidget);
      expect(
        find.text('Scan the code someone shared with you, or paste its link.'),
        findsOneWidget,
      );
      expect(find.text('camera'), findsOneWidget);
      expect(find.text('Paste link'), findsOneWidget);
      expect(
        find.text(
          'A code works once and for a few minutes. If it has run out, ask '
          'for a new one.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('With a client key'), findsOneWidget);
      await shot(tester, '4a');
    });

    testWidgets('the camera region is named for what to point at', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final app = FirstRunHarness();
      await app.start(tester, connected: false);

      // The real camera view carries the name; the test's stands in for it.
      expect(find.text('camera'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('4a2: a camera that is not allowed makes pasting the main '
        'action', (tester) async {
      final app = await setup(tester);

      app.camera.deny();
      await app.settle(tester);

      expect(
        find.text(
          "SignalHub can't use the camera, so it can't scan. Paste the link "
          "instead, or allow the camera in your phone's settings.",
        ),
        findsOneWidget,
      );
      expect(find.text('camera off'), findsOneWidget);
      expect(find.text('camera'), findsNothing);
      expect(
        find.descendant(
          of: byKey('pasteLink'),
          matching: find.text('Paste link'),
        ),
        findsOneWidget,
      );
      // Not an error colour: it is a choice they made.
      final banner = tester.widget<Container>(
        find
            .ancestor(
              of: find.textContaining("can't use the camera"),
              matching: find.byType(Container),
            )
            .first,
      );
      final colors = Theme.of(tester.element(find.text('camera off')))
          .colorScheme;
      expect(
        (banner.decoration! as BoxDecoration).color,
        isNot(colors.errorContainer),
      );
      await shot(tester, '4a2');

      await tester.tap(byKey('openSettings'));
      await app.settle(tester);
      expect(app.settingsOpened, 1);
    });

    testWidgets('4a3: a code that is not an invitation keeps the scanner', (
      tester,
    ) async {
      final app = await setup(tester);

      app.camera.scan('https://example.org');
      await app.settle(tester);

      expect(find.text(SetupFailure.notInvitation.message), findsOneWidget);
      expect(find.text('camera'), findsOneWidget);
      expect(app.backend.requests, isEmpty);
      await shot(tester, '4a3');
    });

    testWidgets('4a3: the code a web page shows says where it goes', (
      tester,
    ) async {
      final app = await setup(tester);

      app.camera.scan('signalhub://signin?code=K7Q-4MX');
      await app.settle(tester);

      expect(
        find.text(
          "That's a sign-in code for a web page. Use Settings › Sign in a "
          'browser.',
        ),
        findsOneWidget,
      );
      expect(app.backend.requests, isEmpty);
    });

    testWidgets('a code the camera keeps seeing is tried once', (tester) async {
      final app = await setup(tester, withCode: false);

      app.camera.scan('https://example.org');
      app.camera.scan('https://example.org');
      await app.settle(tester);
      app.camera.scan(pairingUri);
      await app.settle(tester);
      app.camera.scan(pairingUri);
      await app.settle(tester);

      expect(
        app.backend.requests.where((r) => r.url.path == '/api/v1/pairing'),
        hasLength(1),
      );
    });

    testWidgets('a pasted link that is not an invitation says so', (
      tester,
    ) async {
      final app = await setup(tester);
      mockClipboard(tester);

      await tester.tap(byKey('pasteLink'));
      await tester.pumpAndSettle();
      await tester.enterText(byKey('pairingUri'), 'not a link');
      await tester.tap(byKey('pair'));
      await app.settle(tester);

      expect(find.text(SetupFailure.notInvitation.message), findsOneWidget);
    });

    testWidgets('a link on the clipboard is offered in the field', (
      tester,
    ) async {
      final app = await setup(tester);
      mockClipboard(tester, pairingUri);

      await tester.tap(byKey('pasteLink'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(byKey('pairingUri')).controller?.text,
        pairingUri,
      );
      await tester.tap(byKey('pair'));
      await app.settle(tester);
      expect(app.backend.acceptedKey, pairedClientKey);
    });

    testWidgets('something else on the clipboard is not offered', (
      tester,
    ) async {
      await setup(tester);
      mockClipboard(tester, 'a password');

      await tester.tap(byKey('pasteLink'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(byKey('pairingUri')).controller?.text,
        isEmpty,
      );
    });
  });

  group('a code that cannot be used', () {
    testWidgets('4e: a code that does not work says to ask for a new one', (
      tester,
    ) async {
      final app = await setup(tester, withCode: false);

      app.camera.scan(pairingUri);
      await app.settle(tester);

      expect(
        find.text(
          'This pairing code has expired or was already used. Ask for a new '
          'one.',
        ),
        findsOneWidget,
      );
      // The scanner stays ready for the new code.
      expect(find.text('camera'), findsOneWidget);
      expect(app.controller.phase, ConnectionPhase.disconnected);
      await shot(tester, '4e');
    });

    testWidgets('4a4: a server that cannot be reached names its address, '
        'and Try again reuses the code', (tester) async {
      final app = await setup(tester);
      app.backend.offline = true;

      app.camera.scan(pairingUri);
      await app.settle(tester);

      expect(
        find.text(
          "Can't reach signalhub.test. Check your connection and that the "
          'address is right, then try again.',
        ),
        findsOneWidget,
      );
      expect(find.text('camera'), findsNothing);
      expect(byKey('tryAgain'), findsOneWidget);
      expect(byKey('scanAnother'), findsOneWidget);
      await shot(tester, '4a4');

      app.backend.offline = false;
      await tester.tap(byKey('tryAgain'));
      await app.settle(tester);

      expect(app.controller.phase, ConnectionPhase.connected);
      expect(app.backend.acceptedKey, pairedClientKey);
    });

    testWidgets('Scan another goes back to the scanner', (tester) async {
      final app = await setup(tester);
      app.backend.offline = true;
      app.camera.scan(pairingUri);
      await app.settle(tester);

      await tester.tap(byKey('scanAnother'));
      await app.settle(tester);

      expect(find.text('camera'), findsOneWidget);
      expect(byKey('tryAgain'), findsNothing);
    });

    testWidgets('a server in trouble says so, and Try again reuses the code', (
      tester,
    ) async {
      final app = await setup(tester);
      var redeemed = 0;
      app.redeemOverride = (url, code) async {
        if (redeemed++ == 0) {
          throw const ApiException('Server error', statusCode: 500);
        }
        return app.backend.redeemPairing(url, code);
      };

      app.camera.scan(pairingUri);
      await app.settle(tester);

      expect(
        find.text('SignalHub had a problem. Try again in a moment.'),
        findsOneWidget,
      );
      await tester.tap(byKey('tryAgain'));
      await app.settle(tester);
      expect(app.controller.phase, ConnectionPhase.connected);
    });

    testWidgets('an answer the app cannot read says so', (tester) async {
      final app = await setup(tester);
      app.redeemOverride = (url, code) async =>
          throw const FormatException('bad');

      app.camera.scan(pairingUri);
      await app.settle(tester);

      expect(find.textContaining('unexpected answer'), findsOneWidget);
    });
  });

  group('a client key', () {
    testWidgets('4a6: is typed with the server address, and a wrong one says '
        'so under the key', (tester) async {
      final app = await setup(tester);
      app.backend.acceptedKey = 'shck1_other';

      await tester.tap(find.textContaining('With a client key'));
      await tester.pumpAndSettle();
      expect(find.text('With a client key'), findsOneWidget);
      await tester.enterText(byKey('serverUrl'), serverUrl);
      await tester.enterText(byKey('clientKey'), clientKey);
      await tester.tap(byKey('connect'));
      await app.settle(tester);

      expect(
        find.text("That key isn't valid, or its device was disconnected."),
        findsOneWidget,
      );
      expect(find.text('Back to scanning'), findsOneWidget);
      await shot(tester, '4a6');
      expect(app.store.saved, isNull);

      await tester.tap(byKey('backToScanning'));
      await app.settle(tester);
      expect(find.text('camera'), findsOneWidget);
    });

    testWidgets('an address that cannot be reached is said under the address', (
      tester,
    ) async {
      final app = await setup(tester);
      app.backend.offline = true;

      await tester.tap(byKey('byHand'));
      await tester.pumpAndSettle();
      await tester.enterText(byKey('serverUrl'), serverUrl);
      await tester.enterText(byKey('clientKey'), clientKey);
      await tester.tap(byKey('connect'));
      await app.settle(tester);

      expect(
        find.textContaining("Can't reach signalhub.test."),
        findsOneWidget,
      );
    });

    testWidgets('a bad address and a bad key are said under their fields', (
      tester,
    ) async {
      final app = await setup(tester);
      await tester.tap(byKey('byHand'));
      await tester.pumpAndSettle();

      await tester.enterText(byKey('serverUrl'), 'not a url');
      await tester.enterText(byKey('clientKey'), clientKey);
      await tester.tap(byKey('connect'));
      await app.settle(tester);
      expect(find.textContaining('Enter the server address'), findsOneWidget);

      await tester.enterText(byKey('serverUrl'), serverUrl);
      await tester.enterText(byKey('clientKey'), 'not a key');
      await tester.tap(byKey('connect'));
      await app.settle(tester);
      expect(find.textContaining('Enter a client key'), findsOneWidget);
      expect(app.backend.requests, isEmpty);
    });
  });

  group('a device the server no longer accepts', () {
    testWidgets('4f: is back at setup with a neutral sentence', (tester) async {
      final app = FirstRunHarness();
      app.backend.acceptedKey = null;
      useDesignPhone(tester);

      await app.start(tester);

      expect(app.controller.phase, ConnectionPhase.disconnected);
      expect(
        find.text(
          'This device is no longer connected to SignalHub. To use it again, '
          'ask for a new code, or ask the host.',
        ),
        findsOneWidget,
      );
      expect(app.store.saved, isNull);
      expect(find.text('camera'), findsOneWidget);
      // Neutral: not the error container of a failed code.
      expect(find.byIcon(Icons.link_off), findsOneWidget);
      await shot(tester, '4f');
    });

    testWidgets('the sentence goes when something is tried', (tester) async {
      final app = FirstRunHarness();
      app.backend.acceptedKey = null;
      useDesignPhone(tester);
      await app.start(tester);

      app.camera.scan('https://example.org');
      await app.settle(tester);

      expect(find.textContaining('no longer connected'), findsNothing);
    });

    testWidgets('any 401 while using the app does the same, and takes the '
        'screens with it', (tester) async {
      final app = FirstRunHarness();
      app.backend.publish('e-1', 'Build failed');
      useDesignPhone(tester);
      await app.start(tester);
      await tester.tap(find.text('Build failed'));
      await app.settle(tester);
      expect(find.text('Event'), findsOneWidget);

      app.backend.acceptedKey = null;
      await tester.runAsync(app.controller.refresh);
      // One frame is enough: nothing of the old connection is left over it.
      await tester.pump();

      expect(find.text('Event'), findsNothing);
      expect(find.text('Build failed'), findsNothing);
      expect(find.textContaining('no longer connected'), findsOneWidget);
    });

    testWidgets('disconnecting on purpose says nothing', (tester) async {
      final app = FirstRunHarness();
      useDesignPhone(tester);
      await app.start(tester);

      await tester.runAsync(app.controller.disconnect);
      await app.settle(tester);

      expect(find.textContaining('no longer connected'), findsNothing);
      expect(find.text('camera'), findsOneWidget);
    });
  });

  testWidgets('setup fits 360 dp at 200 % text', (tester) async {
    final app = FirstRunHarness();
    useDesignPhone(tester, size: const Size(360, 800), textScale: 2);
    await app.start(tester, connected: false);

    app.camera.scan('https://example.org');
    await app.settle(tester);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(byKey('byHand'));
    await tester.pumpAndSettle();
    await tester.tap(byKey('byHand'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(byKey('connect'), findsOneWidget);
  });
}
