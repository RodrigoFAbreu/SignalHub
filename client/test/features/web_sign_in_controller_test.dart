import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:signalhub_client/src/features/web_sign_in_controller.dart';

import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/web_sign_in_backend.dart';

void main() {
  late AppHarness app;
  late WebSignInBackend page;
  late WebSignInController sign;

  /// A connected device of [role] and a web page waiting to be signed in.
  Future<void> connected([String role = 'BASIC']) async {
    app = AppHarness(role: role);
    page = WebSignInBackend(app.backend)..add();
    await app.controller.connect(serverUrl, clientKey);
    sign = WebSignInController(app.controller, serverUrl: serverUrl);
  }

  String scanLink([String server = serverUrl, String code = 'shsc1_x']) => Uri(
    scheme: 'signalhub',
    host: 'signin',
    queryParameters: {'server': server, 'code': code},
  ).toString();

  final scanned = scanLink(serverUrl, WebSignInBackend.scanCode);

  group('a scanned code', () {
    test('finds the browser, which only the person signs in', () async {
      await connected();

      await sign.readScanned(scanned);

      expect(sign.step, SignInStep.confirming);
      expect(sign.request!.browserName, 'Firefox on Linux');
      expect(page.lookups, [WebSignInBackend.scanCode]);
      // Scanning alone signs no one in.
      expect(page.approved, isEmpty);
    });

    test('is signed in by approving it, and says which browser', () async {
      await connected();
      await sign.readScanned(scanned);

      await sign.approve();

      expect(sign.step, SignInStep.done);
      expect(sign.signedIn, 'Firefox on Linux');
      expect(page.approved, ['signin-1']);
    });

    test('is cancelled for the page, and not read again while seen', () async {
      await connected();
      await sign.readScanned(scanned);

      await sign.cancel();
      // The camera still sees the same code.
      await sign.readScanned(scanned);

      expect(sign.step, SignInStep.scanning);
      expect(page.cancelled, ['signin-1']);
      expect(page.approved, isEmpty);
      expect(page.lookups, hasLength(1));
    });

    test('is read once while it is being checked', () async {
      await connected();

      await Future.wait([sign.readScanned(scanned), sign.readScanned(scanned)]);

      expect(page.lookups, hasLength(1));
    });

    test('that is not a sign-in link is refused without asking', () async {
      await connected();

      await sign.readScanned('https://example.org/');

      expect(sign.failure!.kind, SignInFailureKind.notSignInCode);
      expect(page.lookups, isEmpty);
    });

    test('a pairing code is not a sign-in code', () async {
      await connected();

      await sign.readScanned(pairingUri);

      expect(sign.failure!.kind, SignInFailureKind.notSignInCode);
      expect(page.requests, isEmpty);
    });

    test('of another server is refused, naming this one', () async {
      await connected();

      await sign.readScanned(scanLink('https://other.test', 'shsc1_abc'));

      expect(sign.failure!.kind, SignInFailureKind.otherServer);
      expect(
        sign.failure!.message,
        'That code is for another server. This app is connected to '
        'signalhub.test.',
      );
      expect(page.lookups, isEmpty);
    });

    test('of this server is read however the address is spelled', () async {
      await connected();

      await sign.readScanned(
        scanLink('HTTPS://SignalHub.test:443/', WebSignInBackend.scanCode),
      );

      expect(sign.step, SignInStep.confirming);
    });

    test('that has run out is a wrong code', () async {
      await connected();
      page.expire();

      await sign.readScanned(scanned);

      expect(sign.failure!.kind, SignInFailureKind.wrongCode);
      expect(sign.step, SignInStep.scanning);
    });
  });

  group('a typed code', () {
    test(
      'is looked up as typed, in any case, with or without the dash',
      () async {
        for (final typed in ['K7Q-4MX', 'k7q4mx', ' k7q 4mx ']) {
          await connected();

          await sign.readTyped(typed);

          expect(sign.step, SignInStep.confirming, reason: typed);
          expect(page.lookups, [typed.trim()]);
        }
      },
    );

    test('that is wrong says so and keeps the field for another try', () async {
      await connected();

      await sign.readTyped('K7Q-4MY');

      expect(sign.failure, same(SignInFailure.wrongCode));
      expect(sign.step, SignInStep.scanning);
      await sign.readTyped('K7Q-4MX');
      expect(sign.step, SignInStep.confirming);
      expect(sign.failure, isNull);
    });

    test('that cannot be a code is not sent, so it uses up no try', () async {
      await connected();

      for (final typed in ['', 'K7Q', 'K7Q-4MXX', 'K7Q-40X', 'K7Q-4MI']) {
        await sign.readTyped(typed);

        expect(sign.failure, same(SignInFailure.wrongCode), reason: typed);
      }
      expect(page.lookups, isEmpty);
      expect(page.wrongTries, 0);
    });

    test('is refused after too many wrong codes, even a right one', () async {
      await connected();

      for (var i = 0; i < WebSignInBackend.triesAllowed; i++) {
        await sign.readTyped('K7Q-4M${'ABCDE'[i]}');
        expect(sign.failure, same(SignInFailure.wrongCode));
      }
      await sign.readTyped('K7Q-4MX');

      expect(sign.failure, same(SignInFailure.tooManyTries));
      expect(
        sign.failure!.message,
        'Too many tries. Wait a few minutes, then try again.',
      );
      expect(sign.failure!.canRetry, isFalse);
      expect(sign.step, SignInStep.scanning);
    });
  });

  group('when something goes wrong', () {
    test('no answer from the server can be tried again', () async {
      await connected();
      app.backend.offline = true;

      await sign.readScanned(scanned);

      expect(sign.failure!.kind, SignInFailureKind.offline);
      expect(
        sign.failure!.message,
        "Can't reach SignalHub. Check your connection and try again.",
      );
      expect(sign.failure!.canRetry, isTrue);

      app.backend.offline = false;
      await sign.retry();

      expect(sign.step, SignInStep.confirming);
      expect(sign.failure, isNull);
    });

    test('a server error says so', () async {
      await connected();
      app.backend.handlers.insert(
        0,
        (request, path) =>
            path.contains('web-sign-ins') ? http.Response('{}', 500) : null,
      );

      await sign.readTyped('K7Q-4MX');

      expect(sign.failure!.kind, SignInFailureKind.other);
      expect(sign.failure!.canRetry, isTrue);
    });

    test(
      'a page that gave up before it was approved ends the sign-in',
      () async {
        await connected();
        await sign.readScanned(scanned);
        page.expire();

        await sign.approve();

        expect(sign.failure, same(SignInFailure.gone));
        expect(sign.step, SignInStep.scanning);
        expect(sign.request, isNull);
      },
    );

    test(
      'an approval that cannot reach the server keeps the question',
      () async {
        await connected();
        await sign.readScanned(scanned);
        page.approveFailsWith = 0;

        await sign.approve();

        expect(sign.step, SignInStep.confirming);
        expect(sign.failure, same(SignInFailure.offline));

        page.approveFailsWith = null;
        await sign.approve();

        expect(sign.step, SignInStep.done);
      },
    );

    test(
      'a device the server no longer accepts ends quietly at setup',
      () async {
        await connected();
        app.backend.acceptedKey = null;

        await sign.readScanned(scanned);

        expect(sign.failure, isNull);
        expect(sign.step, SignInStep.scanning);
      },
    );

    test(
      'a cancel the server could not hear changes nothing for the person',
      () async {
        await connected();
        await sign.readScanned(scanned);
        app.backend.offline = true;

        await sign.cancel();

        expect(sign.step, SignInStep.scanning);
        expect(sign.failure, isNull);
      },
    );
  });
}
