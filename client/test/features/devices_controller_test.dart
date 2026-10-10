import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/app_controller.dart';
import 'package:signalhub_client/src/features/action_failure.dart';
import 'package:signalhub_client/src/features/devices_controller.dart';
import 'package:signalhub_client/src/models/client_registration.dart';
import 'package:signalhub_client/src/models/users.dart';

import '../support/fakes.dart';
import '../support/people_backend.dart';
import '../support/people_fixture.dart';

const thisDevice = '01a0da2c-1f3e-7a51-8d0c-6b1f2e3d4c5b';

void main() {
  late PeopleFixture f;

  /// A connected device of [role]; the controller is the app's own.
  Future<DevicesController> connected(String role) async {
    f = PeopleFixture(role);
    await f.app.controller.connect(serverUrl, clientKey);
    return f.controller.deviceList;
  }

  ManagedDevice device(DevicesController c, String id) => c.byId(id)!;

  group('what it reads', () {
    test('a summary is null until the devices are read', () async {
      final devices = await connected('ADMIN');
      expect(devices.summary, isNull);

      await devices.load();

      // An admin counts everyone's active devices, not the revoked one.
      expect(devices.summary, '7 devices');
    });

    test('a mod and a basic user count their own', () async {
      for (final role in ['MOD', 'BASIC']) {
        final devices = await connected(role);
        await devices.load();

        expect(devices.summary, '2 devices', reason: role);
      }
    });

    test('browsers are counted apart', () async {
      final devices = await connected('MOD');
      await devices.load();
      devices.show([
        for (final d in devices.devices) d,
        ManagedDevice(
          id: 'b',
          name: 'Firefox on Linux',
          admin: false,
          createdAt: DateTime.utc(2026, 10, 1),
          isBrowser: true,
        ),
      ]);

      expect(devices.summary, '3 devices · 1 browser');
    });

    test('one device and none are said as such', () async {
      final devices = await connected('ADMIN');
      await devices.load();

      devices.show([device(devices, thisDevice)]);
      expect(devices.summary, '1 device');
      devices.show(const []);
      expect(devices.summary, 'No devices');
    });

    test('groups put you first, then admins, mods and basic users', () async {
      final devices = await connected('ADMIN');
      f.people.addUser('user-9', 'Aaron', 'BASIC');
      f.people.addDevice('d-aaron', 'Aaron - Phone', 'user-9');
      await devices.load();

      expect(
        [for (final g in devices.groups) g.user!.name],
        ['Rodrigo', 'Sofia', 'Ana', 'Aaron', 'João', 'Marta'],
      );
    });

    test('a person\'s devices: this one first, revoked last', () async {
      final devices = await connected('ADMIN');
      await devices.load();

      expect(
        [for (final d in devices.devicesOf('user-0')) d.name],
        ['Pixel 8', 'Rodrigo - Tablet'],
      );
      expect(
        [for (final d in devices.devicesOf('user-2')) d.name],
        ['Ana - Pixel', 'Ana - Tablet', 'Ana - Old phone'],
      );
    });

    test(
      'a role that changed does not leave other people\'s devices',
      () async {
        final devices = await connected('ADMIN');
        await devices.load();
        f.app.backend
          ..userRole = 'MOD'
          ..admin = false;
        await f.controller.rereadRegistration();

        expect(
          [for (final d in devices.ownDevices) d.name],
          ['Pixel 8', 'Rodrigo - Tablet'],
          reason:
              'the older list stays until it is read again, but only the '
              "caller's user's devices are offered",
        );
      },
    );

    test('a failed read keeps the older list, and says why', () async {
      final devices = await connected('ADMIN');
      await devices.load();

      f.people.failWith = 0;
      await devices.load();

      expect(devices.list.stale, isTrue);
      expect(devices.list.offline, isTrue);
      expect(devices.devices, isNotEmpty);
      f.people.failWith = null;
      await devices.load();
      expect(devices.list.stale, isFalse);
    });

    test('a server without device endpoints is unsupported', () async {
      final devices = await connected('ADMIN');
      f.people.failWith = 404;

      await devices.load();

      expect(devices.unsupported, isTrue);
      f.people.failWith = null;
      await devices.load();
      expect(devices.unsupported, isFalse);
    });

    test('a key the server no longer accepts ends quietly', () async {
      final devices = await connected('ADMIN');
      f.app.backend.acceptedKey = null;

      await devices.load();

      expect(f.controller.phase, ConnectionPhase.disconnected);
      expect(devices.list.error, isNull);
    });

    test('does not notify after it is disposed', () async {
      final devices = await connected('ADMIN');
      var notified = 0;
      devices.addListener(() => notified++);

      final loading = devices.load();
      devices.dispose();
      await loading;

      expect(notified, 1, reason: 'only the start of the read');
    });
  });

  group('changing a device', () {
    test('renames, trimming the name', () async {
      final devices = await connected('MOD');
      await devices.load();

      final failure = await devices.rename(
        device(devices, 'd-tablet'),
        '  Kitchen  ',
      );

      expect(failure, isNull);
      expect(device(devices, 'd-tablet').name, 'Kitchen');
      expect(devices.busyId, isNull);
    });

    test('marks the device it is changing', () async {
      final devices = await connected('MOD');
      await devices.load();
      final seen = <String?>[];
      devices.addListener(() => seen.add(devices.busyId));

      await devices.revoke(device(devices, 'd-tablet'));

      expect(seen.first, 'd-tablet');
      expect(seen.last, isNull);
    });

    test('revokes: for good, and the device is listed revoked', () async {
      final devices = await connected('ADMIN');
      await devices.load();

      expect(await devices.revoke(device(devices, 'd-joao')), isNull);

      expect(device(devices, 'd-joao').isRevoked, isTrue);
    });

    test('deletes a revoked device and drops it', () async {
      final devices = await connected('ADMIN');
      await devices.load();

      expect(await devices.delete(device(devices, 'd-ana-old')), isNull);

      expect(devices.byId('d-ana-old'), isNull);
    });

    test('keeps a browser a browser through a change', () async {
      final devices = await connected('MOD');
      await devices.load();
      f.people.addDevice('d-b', 'Firefox on Linux', PeopleBackend.callerId);
      await devices.load();
      devices.show([
        for (final d in devices.devices)
          d.id == 'd-b'
              ? ManagedDevice(
                  id: d.id,
                  name: d.name,
                  admin: d.admin,
                  createdAt: d.createdAt,
                  user: d.user,
                  isBrowser: true,
                )
              : d,
      ]);

      await devices.revoke(device(devices, 'd-b'));

      expect(device(devices, 'd-b').isRevoked, isTrue);
      expect(device(devices, 'd-b').isBrowser, isTrue);
    });

    test(
      'a refusal for the role says so when the role did not change',
      () async {
        final devices = await connected('MOD');
        await devices.load();
        f.people.failWith = 403;

        final failure = await devices.rename(device(devices, 'd-tablet'), 'x');

        expect(failure!.kind, FailureKind.notAllowed);
        expect(
          failure.message,
          "Your role doesn't allow that. Ask an admin of this server.",
        );
        expect(failure.canRetry, isFalse);
      },
    );

    test(
      'a refusal because the role changed is quiet, and read again',
      () async {
        final devices = await connected('MOD');
        await devices.load();
        f.app.backend.userRole = 'BASIC';

        final failure = await devices.rename(device(devices, 'd-tablet'), 'x');

        expect(failure!.isQuiet, isTrue);
        expect(f.controller.role, UserRole.basic);
        expect(f.controller.hasRoleChange, isTrue);
        // Not tried again.
        expect(
          f.people.requests.where((r) => r.startsWith('PATCH')),
          hasLength(1),
        );
      },
    );

    test('an admin device is explained in words', () async {
      final devices = await connected('ADMIN');
      await devices.load();
      f.people.devices.firstWhere((d) => d['id'] == 'd-ana-tablet')['admin'] =
          true;

      final failure = await devices.revoke(device(devices, 'd-ana-tablet'));

      expect(failure!.kind, FailureKind.adminDevice);
      expect(
        failure.message,
        "That's an admin device. Admin devices are managed on the admin "
        'page.',
      );
      // The list is read again: it is an admin device now.
      expect(device(devices, 'd-ana-tablet').admin, isTrue);
    });

    test('a mod\'s last active device is explained in words', () async {
      final devices = await connected('MOD');
      await devices.load();
      f.people.refuseLastActive = true;

      final failure = await devices.revoke(device(devices, 'd-tablet'));

      expect(failure!.kind, FailureKind.lastActiveDevice);
      expect(
        failure.message,
        "It's your last active device. Revoking it would lock you out. "
        'Connect another device first.',
      );
      expect(device(devices, 'd-tablet').isRevoked, isFalse);
    });

    test('a device that is gone is said, and leaves the list', () async {
      final devices = await connected('MOD');
      await devices.load();
      f.people.devices.removeWhere((d) => d['id'] == 'd-tablet');

      final failure = await devices.rename(device(devices, 'd-tablet'), 'x');

      expect(failure!.kind, FailureKind.gone);
      expect(devices.byId('d-tablet'), isNull);
    });

    test('revoking one that was revoked meanwhile is not a failure', () async {
      final devices = await connected('ADMIN');
      await devices.load();
      final stale = device(devices, 'd-ana-tablet');
      f.people.devices.firstWhere(
        (d) => d['id'] == 'd-ana-tablet',
      )['revokedAt'] = '2026-10-09T09:00:00Z';
      f.people.refuseLastActive = false;

      expect(await devices.revoke(stale), isNull);
    });

    test('renaming a device revoked meanwhile is said', () async {
      final devices = await connected('MOD');
      await devices.load();
      final stale = device(devices, 'd-tablet');
      f.people.devices.firstWhere((d) => d['id'] == 'd-tablet')['revokedAt'] =
          '2026-10-09T09:00:00Z';

      final failure = await devices.rename(stale, 'x');

      expect(
        failure!.message,
        "That device is revoked, so its name can't change.",
      );
    });

    test('deleting one that is gone already is quiet', () async {
      final devices = await connected('ADMIN');
      await devices.load();
      final old = device(devices, 'd-ana-old');
      f.people.devices.removeWhere((d) => d['id'] == 'd-ana-old');
      f.people.failWith = null;

      // The fake answers 404 for a device it no longer has.
      expect(await devices.delete(old), isNull);
      expect(devices.byId('d-ana-old'), isNull);
    });

    test('deleting an active device is said', () async {
      final devices = await connected('ADMIN');
      await devices.load();

      final failure = await devices.delete(device(devices, 'd-joao'));

      expect(
        failure!.message,
        "That device isn't revoked, so it can't be deleted.",
      );
    });

    test('a server that cannot delete devices says so', () async {
      final devices = await connected('ADMIN');
      await devices.load();
      f.people.failWith = 405;

      final failure = await devices.delete(device(devices, 'd-ana-old'));

      expect(failure!.kind, FailureKind.unsupported);
      expect(
        failure.message,
        'This server cannot delete devices. Update SignalHub, or delete it on '
        'the admin page.',
      );
    });

    test('no connection offers Retry, a server error also', () async {
      final devices = await connected('MOD');
      await devices.load();

      f.people.failWith = 0;
      final offline = await devices.rename(device(devices, 'd-tablet'), 'x');
      f.people.failWith = 500;
      final broken = await devices.rename(device(devices, 'd-tablet'), 'x');

      expect(offline!.kind, FailureKind.offline);
      expect(
        offline.message,
        "Couldn't rename Ana - Tablet. Check your connection and try again.",
      );
      expect(offline.canRetry, isTrue);
      expect(broken!.kind, FailureKind.other);
      expect(broken.message, "Couldn't rename Ana - Tablet. Try again.");
      expect(broken.canRetry, isTrue);
    });

    test('a browser is signed out, not revoked, in its words', () async {
      final devices = await connected('MOD');
      f.people.addDevice('d-b', 'Firefox on Linux', PeopleBackend.callerId);
      await devices.load();
      devices.show([
        for (final d in devices.devices)
          d.id == 'd-b'
              ? ManagedDevice(
                  id: d.id,
                  name: d.name,
                  admin: d.admin,
                  createdAt: d.createdAt,
                  user: d.user,
                  isBrowser: true,
                )
              : d,
      ]);
      f.people.failWith = 500;

      final failure = await devices.revoke(device(devices, 'd-b'));

      expect(
        failure!.message,
        "Couldn't sign out Firefox on Linux. Try again.",
      );
    });

    test('a key the server no longer accepts ends quietly', () async {
      final devices = await connected('MOD');
      await devices.load();
      f.app.backend.acceptedKey = null;

      final failure = await devices.rename(device(devices, 'd-tablet'), 'x');

      expect(failure!.isQuiet, isTrue);
      expect(f.controller.phase, ConnectionPhase.disconnected);
    });
  });

  group('when a device was last active', () {
    final now = DateTime(2026, 10, 10, 15);

    ManagedDevice at({
      DateTime? active,
      DateTime? revoked,
      bool browser = false,
    }) => ManagedDevice(
      id: 'd',
      name: 'Phone',
      admin: false,
      createdAt: DateTime(2026, 9, 1),
      lastActiveAt: active,
      revokedAt: revoked,
      isBrowser: browser,
    );

    test('says today, yesterday, days ago, then the date', () {
      String say(DateTime when) => deviceActivity(at(active: when), now);

      expect(say(DateTime(2026, 10, 10, 0, 5)), 'Last active today');
      expect(say(DateTime(2026, 10, 9, 23, 59)), 'Last active yesterday');
      expect(say(DateTime(2026, 10, 7, 8)), 'Last active 3 days ago');
      expect(say(DateTime(2026, 10, 4, 8)), 'Last active 6 days ago');
      expect(say(DateTime(2026, 10, 3, 8)), 'Last active 3 Oct');
      expect(say(DateTime(2025, 12, 24, 8)), 'Last active 24 Dec 2025');
    });

    test('a time ahead of the clock is today', () {
      expect(
        deviceActivity(at(active: DateTime(2026, 10, 10, 15, 2)), now),
        'Last active today',
      );
    });

    test('says when it was not used, and when it was revoked', () {
      expect(deviceActivity(at(), now), 'Not used yet');
      expect(
        deviceActivity(at(revoked: DateTime(2026, 10, 4, 9)), now),
        'Revoked 4 Oct',
      );
      // A revoked device says so even if it was active.
      expect(
        deviceActivity(
          at(active: DateTime(2026, 10, 9), revoked: DateTime(2026, 10, 4, 9)),
          now,
        ),
        'Revoked 4 Oct',
      );
    });

    test('the device in use says so, a browser says when instead', () {
      expect(deviceActivity(at(), now, inUse: true), 'This device');
      expect(
        deviceActivity(at(browser: true), now, inUse: true),
        'Not used yet',
      );
    });

    test('shortDate leaves the year out only for this one', () {
      expect(shortDate(DateTime(2026, 1, 2), now), '2 Jan');
      expect(shortDate(DateTime(2025, 1, 2), now), '2 Jan 2025');
    });
  });
}
