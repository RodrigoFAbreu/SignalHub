import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/models/client_registration.dart';
import 'package:signalhub_client/src/models/producers.dart';
import 'package:signalhub_client/src/models/users.dart';

void main() {
  group('UserRole', () {
    test('reads the wire names and treats an unknown role as basic', () {
      expect(UserRole.parse('ADMIN'), UserRole.admin);
      expect(UserRole.parse('MOD'), UserRole.mod);
      expect(UserRole.parse('BASIC'), UserRole.basic);
      expect(UserRole.parse('OWNER'), UserRole.basic);
    });

    test('says what each role may do', () {
      expect(UserRole.basic.managesDevices, isFalse);
      expect(UserRole.mod.managesDevices, isTrue);
      expect(UserRole.admin.managesDevices, isTrue);
      expect(UserRole.admin.isAdmin, isTrue);
      expect(UserRole.mod.isAdmin, isFalse);
    });

    test('has the words the app shows', () {
      expect(UserRole.values.map((r) => r.label), ['Basic', 'Mod', 'Admin']);
    });
  });

  group('ClientRegistration', () {
    Map<String, Object?> json({Object? user, bool? admin}) => {
      'id': 'c-1',
      'name': 'Pixel',
      'createdAt': '2026-10-10T08:00:00Z',
      'admin': ?admin,
      'user': user,
      'lastActiveAt': '2026-10-10T09:00:00Z',
    };

    test('reads its user, role and when it was last active', () {
      final client = ClientRegistration.fromJson(
        json(user: {'id': 'u-1', 'name': 'Ana', 'role': 'MOD'}, admin: false),
      );

      expect(client.user?.name, 'Ana');
      expect(client.role, UserRole.mod);
      expect(client.lastActiveAt, DateTime.utc(2026, 10, 10, 9));
    });

    test('a server released before users gives a role from admin', () {
      expect(
        ClientRegistration.fromJson(json(admin: true)).role,
        UserRole.admin,
      );
      expect(ClientRegistration.fromJson(json()).role, UserRole.basic);
      expect(ClientRegistration.fromJson(json()).user, isNull);
    });
  });

  group('ManagedDevice', () {
    test('reads its user and last active time; a device is no browser', () {
      final device = ManagedDevice.fromJson({
        'id': 'c-2',
        'name': 'Tablet',
        'admin': false,
        'createdAt': '2026-10-10T08:00:00Z',
        'revokedAt': null,
        'lastActiveAt': null,
        'user': {'id': 'u-1', 'name': 'Ana', 'role': 'BASIC'},
      });

      expect(device.user?.role, UserRole.basic);
      expect(device.lastActiveAt, isNull);
      expect(device.isBrowser, isFalse);
      expect(device.isRevoked, isFalse);
      expect(device.withName('Kitchen').name, 'Kitchen');
      expect(device.withName('Kitchen').user?.name, 'Ana');
    });
  });

  group('Person', () {
    test('a name only, for a basic or mod key', () {
      final person = Person.fromJson({'id': 'u-1', 'name': 'Ana'});

      expect(person.role, isNull);
      expect(person.activeDevices, isNull);
      expect(person.hasPaired, isNull);
    });

    test('role, active devices and whether they paired, for an admin', () {
      final person = Person.fromJson({
        'id': 'u-1',
        'name': 'Rui',
        'role': 'BASIC',
        'activeDevices': 0,
        'hasPaired': false,
      });

      expect(person.role, UserRole.basic);
      expect(person.activeDevices, 0);
      expect(person.hasPaired, isFalse);
      expect(person.withRole(UserRole.mod).role, UserRole.mod);
      expect(person.withRole(UserRole.mod).name, 'Rui');
    });

    test('a person\'s producer: visibility and whether it is disabled', () {
      final producer = PersonProducer.fromJson({
        'id': 'p-1',
        'name': 'garage-door',
        'visibility': 'PUBLIC',
        'disabled': true,
      });

      expect(producer.visibility, ProducerVisibility.public);
      expect(producer.disabled, isTrue);
    });
  });

  group('producers', () {
    test('a visible producer', () {
      final producer = VisibleProducer.fromJson({
        'id': 'p-1',
        'name': 'ana-reports',
        'owner': {'id': 'u-1', 'name': 'Ana'},
        'visibility': 'PUBLIC',
        'disabled': false,
        'subscribed': false,
      });

      expect(producer.owner.name, 'Ana');
      expect(producer.withSubscribed(true).subscribed, isTrue);
      expect(producer.withSubscribed(true).name, 'ana-reports');
    });

    test('an unknown visibility counts as private', () {
      expect(ProducerVisibility.parse('SECRET'), ProducerVisibility.private);
    });

    Map<String, Object?> own() => {
      'id': 'p-1',
      'name': 'ci-pipeline',
      'createdAt': '2026-10-10T08:00:00Z',
      'disabledAt': null,
      'disabledByOperator': false,
      'lastEventAt': '2026-10-10T09:00:00Z',
      'visibility': 'PRIVATE',
      'subscribed': true,
      'allowedUsers': [
        {'id': 'u-2', 'name': 'Ana'},
      ],
      'keys': [
        {
          'id': 'k-1',
          'prefix': 'shpk1_EXAMPLE1',
          'createdAt': '2026-10-10T08:00:00Z',
          'lastUsedAt': null,
          'revokedAt': null,
        },
        {
          'id': 'k-2',
          'prefix': 'shpk1_EXAMPLE2',
          'createdAt': '2026-10-10T08:00:00Z',
          'lastUsedAt': '2026-10-10T09:00:00Z',
          'revokedAt': '2026-10-10T09:30:00Z',
        },
      ],
    };

    test('an own producer counts only the keys that still work', () {
      final producer = OwnProducer.fromJson(own());

      expect(producer.allowedUsers.single.name, 'Ana');
      expect(producer.keys, hasLength(2));
      expect(producer.workingKeys.map((k) => k.id), ['k-1']);
      expect(producer.keys.last.isRevoked, isTrue);
      expect(producer.isDisabled, isFalse);
      expect(producer.disabledByOperator, isFalse);
    });

    test('a disabled producer says who disabled it', () {
      final producer = OwnProducer.fromJson({
        ...own(),
        'disabledAt': '2026-10-10T10:00:00Z',
        'disabledByOperator': true,
      });

      expect(producer.isDisabled, isTrue);
      expect(producer.disabledByOperator, isTrue);
    });

    test('a server that does not say when a key was used or why a producer '
        'is disabled still reads', () {
      final json = own();
      for (final key in json['keys']! as List<Object?>) {
        (key! as Map<String, Object?>).remove('lastUsedAt');
      }
      json.remove('disabledByOperator');

      final producer = OwnProducer.fromJson(json);

      expect(producer.keys.first.lastUsedAt, isNull);
      expect(producer.disabledByOperator, isFalse);
    });

    test('an issued key never prints', () {
      final issued = IssuedProducerKey.fromJson({
        'producer': own(),
        'keyId': 'k-1',
        'apiKey': 'shpk1_EXAMPLEKEY-not-a-real-key-0000',
      });

      expect(issued.apiKey, startsWith('shpk1_'));
      expect('$issued', isNot(contains('EXAMPLEKEY')));
    });

    test('the server\'s release', () {
      final server = ServerInfo.fromJson({'version': '3.4.0', 'commit': null});

      expect(server.version, '3.4.0');
      expect(server.commit, isNull);
    });
  });

  group('DevicePairing', () {
    test('names the user the new device belongs to', () {
      final pairing = DevicePairing.fromJson({
        'id': 'pairing-1',
        'name': 'First device',
        'code': 'shpc1_secret',
        'expiresAt': '2026-10-10T08:10:00Z',
        'uri': null,
        'user': {'id': 'u-9', 'name': 'Rui', 'role': 'BASIC'},
      });

      expect(pairing.user?.name, 'Rui');
      expect('$pairing', isNot(contains('secret')));
    });
  });
}
