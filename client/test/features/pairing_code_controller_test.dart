import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/app_controller.dart';
import 'package:signalhub_client/src/connection/pairing_uri.dart';
import 'package:signalhub_client/src/features/action_failure.dart';
import 'package:signalhub_client/src/features/pairing_code_controller.dart';
import 'package:signalhub_client/src/models/users.dart';

import '../support/fakes.dart';
import '../support/people_fixture.dart';

void main() {
  late PeopleFixture f;

  Future<PairingCodeController> connected(String role) async {
    f = PeopleFixture(role);
    await f.app.controller.connect(serverUrl, clientKey);
    return PairingCodeController(
      f.controller,
      serverUrl: serverUrl,
      now: () => f.now,
    );
  }

  group('making a code', () {
    test('for this device\'s own user', () async {
      final code = await connected('MOD');

      await code.create('  Ana - Phone 2  ');

      expect(code.failure, isNull);
      expect(code.pairing!.name, 'Ana - Phone 2');
      expect(code.pairing!.user!.name, 'Ana');
      expect(f.people.pairingsMade, [
        (name: 'Ana - Phone 2', userId: 'user-0'),
      ]);
      expect(code.creating, isFalse);
    });

    test('for someone else, as an admin', () async {
      final code = await connected('ADMIN');

      await code.create('Ana - Phone 2', userId: 'user-2');

      expect(code.pairing!.user!.id, 'user-2');
      expect(f.people.pairingsMade.single.userId, 'user-2');
    });

    test('the link is the server\'s own pairing URI', () async {
      final code = await connected('MOD');
      await code.create('Phone');

      expect(code.link, code.pairing!.uri);
      final parsed = PairingUri.parse(code.link!);
      expect(parsed.serverUrl, serverUrl);
      expect(parsed.code, code.pairing!.code);
    });

    test(
      'with no public address the link is built from this server\'s',
      () async {
        final code = await connected('MOD');
        f.people.pairingUris = false;
        await code.create('Phone');

        expect(code.pairing!.uri, isNull);
        expect(PairingUri.parse(code.link!).serverUrl, serverUrl);
        expect(PairingUri.parse(code.link!).code, code.pairing!.code);
      },
    );

    test('someone removed meanwhile is said, by either answer', () async {
      for (final status in [404, 409]) {
        final code = await connected('ADMIN');
        f.people
          ..userById('user-4')!.removed = true
          ..removedPairingStatus = status;

        await code.create('Phone', userId: 'user-4', personName: 'Marta');

        expect(code.failure!.kind, FailureKind.removed, reason: '$status');
        expect(
          code.failure!.message,
          "Marta's access was removed. Choose someone else.",
        );
        expect(code.pairing, isNull);
      }
    });

    test('a server without pairing from a device says so', () async {
      final code = await connected('MOD');
      f.people.failWith = 404;

      await code.create('Phone');

      expect(code.failure!.kind, FailureKind.unsupported);
      expect(
        code.failure!.message,
        'This server cannot create pairing codes from a device. Update '
        'SignalHub, or create the code on the admin page.',
      );
    });

    test('no connection and a server error are said, with a retry', () async {
      final code = await connected('MOD');

      f.people.failWith = 0;
      await code.create('Phone');
      expect(code.failure!.kind, FailureKind.offline);
      expect(
        code.failure!.message,
        "Couldn't make the code. Check your connection and try again.",
      );

      f.people.failWith = 500;
      await code.create('Phone');
      expect(code.failure!.kind, FailureKind.other);
      expect(code.failure!.canRetry, isTrue);

      f.people.failWith = null;
      await code.create('Phone');
      expect(code.failure, isNull);
    });

    test('a role that changed is quiet; one that did not is said', () async {
      final code = await connected('MOD');
      f.people.failWith = 403;
      await code.create('Phone');
      expect(code.failure!.kind, FailureKind.notAllowed);

      f.people.failWith = null;
      f.app.backend.userRole = 'BASIC';
      await code.create('Phone');
      expect(code.failure!.isQuiet, isTrue);
      expect(f.controller.role, UserRole.basic);
    });

    test('a key the server no longer accepts ends quietly', () async {
      final code = await connected('MOD');
      f.app.backend.acceptedKey = null;

      await code.create('Phone');

      expect(code.failure!.isQuiet, isTrue);
      expect(f.controller.phase, ConnectionPhase.disconnected);
    });

    test('forget leaves nothing of the code', () async {
      final code = await connected('MOD');
      await code.create('Phone');

      code.forget();

      expect(code.pairing, isNull);
      expect(code.link, isNull);
      expect(code.isUsed, isFalse);
    });

    test('does not notify after it is disposed', () async {
      final code = await connected('MOD');
      var notified = 0;
      code.addListener(() => notified++);

      final making = code.create('Phone');
      code.dispose();
      await making;

      expect(notified, 1);
    });
  });

  group('how long it lasts', () {
    test('counts down to its end, and then it is expired', () async {
      final code = await connected('MOD');
      await code.create('Phone');

      expect(code.left, const Duration(minutes: 10));
      expect(code.isExpired, isFalse);

      f.now = f.now.add(const Duration(minutes: 9, seconds: 59));
      expect(code.left, const Duration(seconds: 1));
      expect(code.isExpired, isFalse);

      f.now = f.now.add(const Duration(seconds: 1));
      expect(code.isExpired, isTrue);
    });

    test('a used code is not expired, whatever the time', () async {
      final code = await connected('MOD');
      await code.create('Phone');
      f.people.usePairing('Phone 2');
      await code.check();

      f.now = f.now.add(const Duration(hours: 1));

      expect(code.isUsed, isTrue);
      expect(code.isExpired, isFalse);
    });
  });

  group('whether it was used', () {
    int asked() => f.people.requests
        .where((r) => r.startsWith('GET /api/v1/client/pairings/'))
        .length;

    test('says which device used it', () async {
      final code = await connected('MOD');
      await code.create('Phone');
      await code.check();
      expect(code.usedBy, isNull);

      f.people.usePairing('Ana - Phone 2');
      await code.check();

      expect(code.usedBy, 'Ana - Phone 2');
      expect(code.isUsed, isTrue);
    });

    test('is not asked again once it is known', () async {
      final code = await connected('MOD');
      await code.create('Phone');
      f.people.usePairing('Phone 2');
      await code.check();
      final before = asked();

      await code.check();

      expect(asked(), before);
    });

    test('is not asked before there is a code', () async {
      final code = await connected('MOD');

      await code.check();

      expect(asked(), 0);
    });

    test('a server that cannot say stops being asked', () async {
      for (final status in [404, 405, 403]) {
        final code = await connected('MOD');
        await code.create('Phone');
        f.people.failWith = status;

        await code.check();
        await code.check();
        await code.check();

        expect(asked(), 1, reason: '$status');
        expect(code.pairing, isNotNull);
      }
    });

    test('another failure is left to the next time', () async {
      final code = await connected('MOD');
      await code.create('Phone');
      f.people.failWith = 0;
      await code.check();
      f.people.failWith = null;
      f.people.usePairing('Phone 2');

      await code.check();

      expect(code.usedBy, 'Phone 2');
    });

    test(
      'an answer for a code made or forgotten meanwhile is ignored',
      () async {
        final code = await connected('MOD');
        await code.create('Phone');
        f.people.usePairing('Phone 2');

        final asking = code.check();
        code.forget();
        await asking;

        expect(code.usedBy, isNull);
      },
    );

    test('asks once at a time', () async {
      final code = await connected('MOD');
      await code.create('Phone');

      await Future.wait([code.check(), code.check(), code.check()]);

      expect(asked(), 1);
    });

    test('a key the server no longer accepts ends quietly', () async {
      final code = await connected('MOD');
      await code.create('Phone');
      f.app.backend.acceptedKey = null;

      await code.check();

      expect(f.controller.phase, ConnectionPhase.disconnected);
      expect(code.usedBy, isNull);
    });
  });
}
