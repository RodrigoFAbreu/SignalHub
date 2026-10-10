import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/app_controller.dart';
import 'package:signalhub_client/src/features/action_failure.dart';
import 'package:signalhub_client/src/features/people_controller.dart';
import 'package:signalhub_client/src/models/users.dart';

import '../support/fakes.dart';
import '../support/people_fixture.dart';

void main() {
  late PeopleFixture f;

  Future<PeopleController> connected(String role) async {
    f = PeopleFixture(role);
    await f.app.controller.connect(serverUrl, clientKey);
    return f.controller.people;
  }

  group('the list', () {
    test('is read by role, as the server lists it', () async {
      final people = await connected('ADMIN');

      await people.load();

      expect(
        [for (final p in people.withRole(UserRole.admin)) p.name],
        ['Rodrigo', 'Sofia'],
      );
      expect([for (final p in people.withRole(UserRole.mod)) p.name], ['Ana']);
      expect(
        [for (final p in people.withRole(UserRole.basic)) p.name],
        ['João', 'Marta', 'Rui'],
      );
      expect(people.byId('user-5')!.hasPaired, isFalse);
      expect(people.byId('user-2')!.activeDevices, 2);
      expect(people.byId('user-4')!.activeDevices, 1);
    });

    test('a failed read keeps the older list', () async {
      final people = await connected('ADMIN');
      await people.load();

      f.people.failWith = 0;
      await people.load();

      expect(people.list.stale, isTrue);
      expect(people.people, isNotEmpty);
    });

    test('a first read that fails has no list', () async {
      final people = await connected('ADMIN');
      f.people.failWith = 500;

      await people.load();

      expect(people.list.failedWithoutList, isTrue);
    });

    test('a key the server no longer accepts ends quietly', () async {
      final people = await connected('ADMIN');
      f.app.backend.acceptedKey = null;

      await people.load();

      expect(f.controller.phase, ConnectionPhase.disconnected);
      expect(people.list.error, isNull);
    });

    test('a person who left the list is known to be removed', () async {
      final people = await connected('ADMIN');
      expect(people.wasRemoved('user-4'), isFalse, reason: 'nothing read yet');
      await people.load();
      expect(people.wasRemoved('user-4'), isFalse);

      f.people.userById('user-4')!.removed = true;
      await people.load();

      expect(people.wasRemoved('user-4'), isTrue);
    });

    test('does not notify after it is disposed', () async {
      final people = await connected('ADMIN');
      var notified = 0;
      people.addListener(() => notified++);

      final loading = people.load();
      people.dispose();
      await loading;

      expect(notified, 1);
    });
  });

  group('a person\'s producers', () {
    test('are read when asked, name and visibility', () async {
      final people = await connected('ADMIN');
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

      await people.loadProducers('user-2');

      final producers = people.producersOf('user-2').value!;
      expect(
        [for (final p in producers) p.name],
        ['ana-reports', 'garage-door'],
      );
      expect(producers.last.visibility, ProducerVisibility.private);
      expect(producers.last.disabled, isTrue);
      expect(people.wasRemoved('user-2'), isFalse);
    });

    test('a person who is unknown or removed is known to be removed', () async {
      final people = await connected('ADMIN');
      f.people.userById('user-4')!.removed = true;

      await people.loadProducers('user-4');
      expect(people.wasRemoved('user-4'), isTrue);

      // A revoked user answers 409 on a server that says so.
      f.people.producersFailWith = 409;
      await people.loadProducers('user-3');
      expect(people.wasRemoved('user-3'), isTrue);
    });

    test('a failure that is not a removal is not one', () async {
      final people = await connected('ADMIN');
      f.people.producersFailWith = 0;

      await people.loadProducers('user-2');

      expect(people.producersOf('user-2').failedWithoutList, isTrue);
      expect(people.wasRemoved('user-2'), isFalse);
    });
  });

  group('inviting', () {
    test('makes the person and the code of their first device', () async {
      final people = await connected('ADMIN');

      final result = await people.invite(
        'Luna',
        role: UserRole.mod,
        deviceName: 'Luna - iPhone',
      );

      expect(result.failure, isNull);
      expect(result.user!.name, 'Luna');
      expect(result.user!.role, UserRole.mod);
      expect(result.pairing!.name, 'Luna - iPhone');
      expect(result.pairing!.code, startsWith('shpc1_'));
      expect(f.people.userById(result.user!.id)!.role, 'MOD');
    });

    test('a name that is taken is said, ignoring capitals', () async {
      final people = await connected('ADMIN');

      final result = await people.invite('ANA', role: UserRole.basic);

      expect(result.failure!.kind, FailureKind.nameTaken);
      expect(
        result.failure!.message,
        'Someone on this server already has that name. Use another.',
      );
      expect(result.user, isNull);
    });

    test('no connection offers a retry', () async {
      final people = await connected('ADMIN');
      f.people.failWith = 0;

      final result = await people.invite('Luna', role: UserRole.basic);

      expect(result.failure!.kind, FailureKind.offline);
      expect(
        result.failure!.message,
        "Couldn't make the invitation. Check your connection and try again.",
      );
      expect(result.failure!.canRetry, isTrue);
    });

    test('a refusal that is not a role change says so in words', () async {
      final people = await connected('ADMIN');
      f.people.failWith = 403;

      final result = await people.invite('Luna', role: UserRole.basic);

      expect(result.failure!.kind, FailureKind.notAllowed);
    });

    test('a role that changed meanwhile is quiet and read again', () async {
      final people = await connected('ADMIN');
      f.app.backend
        ..userRole = 'MOD'
        ..admin = false;

      final result = await people.invite('Luna', role: UserRole.basic);

      expect(result.failure!.isQuiet, isTrue);
      expect(f.controller.role, UserRole.mod);
      expect(f.people.users.where((u) => u.name == 'Luna'), isEmpty);
    });

    test('a key the server no longer accepts ends quietly', () async {
      final people = await connected('ADMIN');
      f.app.backend.acceptedKey = null;

      final result = await people.invite('Luna', role: UserRole.basic);

      expect(result.failure!.isQuiet, isTrue);
      expect(f.controller.phase, ConnectionPhase.disconnected);
    });
  });

  group('setting a role', () {
    test('changes it in the list', () async {
      final people = await connected('ADMIN');
      await people.load();

      final failure = await people.setRole(
        people.byId('user-2')!,
        UserRole.basic,
      );

      expect(failure, isNull);
      expect(people.byId('user-2')!.role, UserRole.basic);
      expect(people.changingId, isNull);
    });

    test('marks who is being changed', () async {
      final people = await connected('ADMIN');
      await people.load();
      final seen = <String?>[];
      people.addListener(() => seen.add(people.changingId));

      await people.setRole(people.byId('user-2')!, UserRole.basic);

      expect(seen.first, 'user-2');
      expect(seen.last, isNull);
    });

    test(
      'someone removed meanwhile is said, and known to be removed',
      () async {
        final people = await connected('ADMIN');
        await people.load();
        final marta = people.byId('user-4')!;
        f.people.userById('user-4')!.removed = true;

        final failure = await people.setRole(marta, UserRole.mod);

        expect(failure!.kind, FailureKind.removed);
        expect(
          failure.message,
          "Marta's access was removed, so their role can't change.",
        );
        expect(people.wasRemoved('user-4'), isTrue);
      },
    );

    test('an unknown person (404) is removed too', () async {
      final people = await connected('ADMIN');
      await people.load();
      final marta = people.byId('user-4')!;
      f.people.users.removeWhere((u) => u.id == 'user-4');

      final failure = await people.setRole(marta, UserRole.mod);

      expect(failure!.kind, FailureKind.removed);
    });

    test('someone made an admin meanwhile is said', () async {
      final people = await connected('ADMIN');
      await people.load();
      final marta = people.byId('user-4')!;
      f.people.userById('user-4')!.role = 'ADMIN';

      final failure = await people.setRole(marta, UserRole.mod);

      expect(failure!.kind, FailureKind.adminTarget);
      expect(
        failure.message,
        'Marta is an admin. Admins are managed on the admin page.',
      );
      // And the list says so.
      expect(people.byId('user-4')!.role, UserRole.admin);
    });

    test('no connection offers a retry', () async {
      final people = await connected('ADMIN');
      await people.load();
      f.people.failWith = 0;

      final failure = await people.setRole(
        people.byId('user-2')!,
        UserRole.basic,
      );

      expect(failure!.kind, FailureKind.offline);
      expect(
        failure.message,
        "Couldn't change the role. Check your connection and try again.",
      );
      expect(failure.canRetry, isTrue);
      expect(people.byId('user-2')!.role, UserRole.mod);
    });

    test('a role that changed meanwhile is quiet', () async {
      final people = await connected('ADMIN');
      await people.load();
      f.app.backend
        ..userRole = 'MOD'
        ..admin = false;

      final failure = await people.setRole(
        people.byId('user-2')!,
        UserRole.basic,
      );

      expect(failure!.isQuiet, isTrue);
      expect(f.controller.hasRoleChange, isTrue);
    });

    test('a 403 that is not a role change says so', () async {
      final people = await connected('ADMIN');
      await people.load();
      f.people.failWith = 403;

      final failure = await people.setRole(
        people.byId('user-2')!,
        UserRole.basic,
      );

      expect(failure!.kind, FailureKind.notAllowed);
    });
  });
}
