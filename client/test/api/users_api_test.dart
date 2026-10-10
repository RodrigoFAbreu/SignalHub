import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:signalhub_client/src/api/signalhub_api.dart';
import 'package:signalhub_client/src/connection/server_credentials.dart';
import 'package:signalhub_client/src/models/users.dart';

import '../support/fakes.dart';

/// The calls of the self-service API, each against the path and body the
/// backend documents (docs/architecture.md, "Clients").
void main() {
  final requests = <http.Request>[];
  Object answer = const <String, Object?>{};
  var status = 200;

  late SignalHubApi api;

  setUp(() {
    requests.clear();
    answer = const <String, Object?>{};
    status = 200;
    api = SignalHubApi(
      ServerCredentials.parse(serverUrl, clientKey),
      MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(answer),
          status,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });

  String call() => '${requests.last.method} ${requests.last.url.path}';
  Object? sent() => jsonDecode(requests.last.body);

  Map<String, Object?> producer([String id = 'p-1']) => {
    'id': id,
    'name': 'ci-pipeline',
    'createdAt': '2026-10-10T08:00:00Z',
    'visibility': 'PRIVATE',
    'subscribed': true,
    'allowedUsers': <Object?>[],
    'keys': <Object?>[],
  };

  Map<String, Object?> visible() => {
    'id': 'p-1',
    'name': 'ana-reports',
    'owner': {'id': 'u-1', 'name': 'Ana'},
    'visibility': 'PUBLIC',
    'disabled': false,
    'subscribed': true,
  };

  test('every request carries the client key', () async {
    answer = {'items': <Object?>[]};

    await api.listVisibleProducers();

    expect(requests.last.headers['Authorization'], 'Bearer $clientKey');
  });

  group('subscriptions', () {
    test('lists the producers this user sees', () async {
      answer = {
        'items': [visible()],
      };

      final producers = await api.listVisibleProducers();

      expect(call(), 'GET /api/v1/client/visible-producers');
      expect(producers.single.owner.name, 'Ana');
    });

    test('subscribes and unsubscribes', () async {
      answer = visible();

      final on = await api.subscribe('p-1');
      expect(call(), 'PUT /api/v1/client/visible-producers/p-1/subscription');
      expect(on.subscribed, isTrue);

      await api.unsubscribe('p-1');
      expect(
        call(),
        'DELETE /api/v1/client/visible-producers/p-1/subscription',
      );
    });

    test('a producer this user does not see is a 404', () async {
      status = 404;
      answer = {'title': 'Not Found', 'status': 404};

      await expectLater(
        api.subscribe('p-9'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 404)),
      );
    });
  });

  group('own producers', () {
    test('lists and reads', () async {
      answer = {
        'items': [producer()],
      };
      expect((await api.listOwnProducers()).single.name, 'ci-pipeline');
      expect(call(), 'GET /api/v1/client/producers');

      answer = producer();
      await api.getOwnProducer('p-1');
      expect(call(), 'GET /api/v1/client/producers/p-1');
    });

    test('creates a producer, private unless said otherwise', () async {
      answer = {
        'producer': producer(),
        'keyId': 'k-1',
        'apiKey': 'shpk1_EXAMPLEKEY-not-a-real-key-0000',
      };

      final issued = await api.createProducer('ci-pipeline');

      expect(call(), 'POST /api/v1/client/producers');
      expect(sent(), {'name': 'ci-pipeline', 'visibility': 'PRIVATE'});
      expect(issued.apiKey, startsWith('shpk1_'));

      await api.createProducer(
        'ci-pipeline',
        visibility: ProducerVisibility.public,
      );
      expect(sent(), {'name': 'ci-pipeline', 'visibility': 'PUBLIC'});
    });

    test('a taken name is a 409 with the server\'s title', () async {
      status = 409;
      answer = {'title': 'Producer name is taken', 'status': 409};

      await expectLater(
        api.createProducer('ci-pipeline'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'status', 409)
              .having((e) => e.message, 'message', contains('taken')),
        ),
      );
    });

    test('renames and sets visibility, sending only what changes', () async {
      answer = producer();

      await api.updateProducer('p-1', name: 'builds');
      expect(call(), 'PATCH /api/v1/client/producers/p-1');
      expect(sent(), {'name': 'builds'});

      await api.updateProducer('p-1', visibility: ProducerVisibility.public);
      expect(sent(), {'visibility': 'PUBLIC'});
    });

    test('issues, revokes, disables and enables', () async {
      answer = {'producer': producer(), 'keyId': 'k-2', 'apiKey': 'shpk1_x'};
      await api.issueProducerKey('p-1');
      expect(call(), 'POST /api/v1/client/producers/p-1/keys');

      answer = producer();
      await api.revokeProducerKey('p-1', 'k-1');
      expect(call(), 'POST /api/v1/client/producers/p-1/keys/k-1/revoke');
      await api.disableProducer('p-1');
      expect(call(), 'POST /api/v1/client/producers/p-1/disable');
      await api.enableProducer('p-1');
      expect(call(), 'POST /api/v1/client/producers/p-1/enable');
    });

    test('allows and disallows a user', () async {
      answer = producer();

      await api.allowUser('p-1', 'u-2');
      expect(call(), 'PUT /api/v1/client/producers/p-1/allowed-users/u-2');
      await api.disallowUser('p-1', 'u-2');
      expect(call(), 'DELETE /api/v1/client/producers/p-1/allowed-users/u-2');
    });

    test('an id that needs escaping is escaped', () async {
      answer = producer();

      await api.getOwnProducer('a/b');

      expect(requests.last.url.path, '/api/v1/client/producers/a%2Fb');
    });
  });

  group('people', () {
    test('lists names for anyone and details for an admin', () async {
      answer = {
        'items': [
          {'id': 'u-1', 'name': 'Ana'},
        ],
      };
      expect((await api.listPeople()).single.role, isNull);
      expect(call(), 'GET /api/v1/client/users');

      answer = {
        'items': [
          {
            'id': 'u-1',
            'name': 'Ana',
            'role': 'MOD',
            'activeDevices': 2,
            'hasPaired': true,
          },
        ],
      };
      expect((await api.listPeople()).single.activeDevices, 2);
    });

    test('lists a person\'s producers', () async {
      answer = {
        'items': [
          {
            'id': 'p-1',
            'name': 'garage-door',
            'visibility': 'PRIVATE',
            'disabled': false,
          },
        ],
      };

      final producers = await api.listPersonProducers('u-1');

      expect(call(), 'GET /api/v1/client/users/u-1/producers');
      expect(producers.single.name, 'garage-door');
    });

    test('invites a person with the first device\'s code', () async {
      status = 201;
      answer = {
        'user': {'id': 'u-9', 'name': 'Rui', 'role': 'BASIC'},
        'pairing': {
          'id': 'pairing-1',
          'name': 'First device',
          'code': 'shpc1_secret',
          'expiresAt': '2026-10-10T08:10:00Z',
          'uri': null,
        },
      };

      final invited = await api.inviteUser(
        'Rui',
        role: UserRole.basic,
        deviceName: 'First device',
      );

      expect(call(), 'POST /api/v1/client/users');
      expect(sent(), {
        'name': 'Rui',
        'role': 'BASIC',
        'deviceName': 'First device',
      });
      expect(invited.user.name, 'Rui');
      expect(invited.pairing.code, 'shpc1_secret');
    });

    test('sets a role', () async {
      answer = {'id': 'u-1', 'name': 'Ana', 'role': 'MOD'};

      final user = await api.setUserRole('u-1', UserRole.mod);

      expect(call(), 'PATCH /api/v1/client/users/u-1');
      expect(sent(), {'role': 'MOD'});
      expect(user.role, UserRole.mod);
    });
  });

  group('devices and the server', () {
    test(
      'creates a pairing for oneself or, as an admin, for another',
      () async {
        answer = {
          'id': 'pairing-1',
          'name': 'Tablet',
          'code': 'shpc1_secret',
          'expiresAt': '2026-10-10T08:10:00Z',
        };

        await api.createPairing('Tablet');
        expect(sent(), {'name': 'Tablet'});

        await api.createPairing('Tablet', userId: 'u-2');
        expect(call(), 'POST /api/v1/client/pairings');
        expect(sent(), {'name': 'Tablet', 'userId': 'u-2'});
      },
    );

    test('reads the server\'s release', () async {
      answer = {'version': '3.4.0', 'commit': 'a1b2c3d4e5f6'};

      final server = await api.getServer();

      expect(call(), 'GET /api/v1/client/server');
      expect(server.version, '3.4.0');
      expect(server.commit, 'a1b2c3d4e5f6');
    });

    test('a body that is not the contract is an unexpected answer', () async {
      answer = {'items': 'nope'};

      await expectLater(
        api.listPeople(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'The server sent an unexpected answer',
          ),
        ),
      );
    });
  });
}
