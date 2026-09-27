import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:signalhub_client/src/api/signalhub_api.dart';
import 'package:signalhub_client/src/connection/server_credentials.dart';
import 'package:signalhub_client/src/models/client_registration.dart';
import 'package:signalhub_client/src/models/event.dart';
import 'package:signalhub_client/src/models/inbox_filter.dart';

import '../support/fakes.dart';

void main() {
  late FakeBackend backend;

  setUp(() => backend = FakeBackend());

  test('sends the client key as a bearer credential', () async {
    final client = await backend.api().getClient();

    expect(client.name, 'Pixel 8');
    expect(client.pushTarget, isNull);
    final request = backend.requests.single;
    expect(request.url.toString(), '$serverUrl/api/v1/client');
    expect(request.headers['Authorization'], 'Bearer $clientKey');
    expect(request.headers['Accept'], 'application/json');
  });

  test('redeems a pairing code for a client and its key', () async {
    backend
      ..acceptedKey = null
      ..pairingCodes.add(pairingCode);

    final paired = await backend.redeemPairing(serverUrl, pairingCode);

    expect(paired.clientKey, pairedClientKey);
    expect(paired.registration.name, 'Pixel 8');
    final request = backend.requests.single;
    expect(request.method, 'POST');
    expect(request.url.toString(), '$serverUrl/api/v1/pairing');
    expect(request.headers['Authorization'], 'Bearer $pairingCode');
    expect(request.body, isEmpty);
  });

  test('a used or unknown pairing code is rejected as such', () async {
    backend.pairingCodes.add(pairingCode);
    await backend.redeemPairing(serverUrl, pairingCode);

    expect(
      () => backend.redeemPairing(serverUrl, pairingCode),
      throwsA(isA<PairingRejectedException>()),
    );
  });

  test('keeps a base path, for servers behind a reverse proxy', () async {
    await backend.api('https://example.org/signalhub/').getClient();

    expect(
      backend.requests.single.url.toString(),
      'https://example.org/signalhub/api/v1/client',
    );
  });

  test('reads the push options the server serves', () async {
    backend.pushConfig = servedPushConfig;

    final config = (await backend.api().getPushConfig())!;

    expect(config.provider, 'fcm');
    expect(config.options['FIREBASE_PROJECT_ID'], 'owner-project');
    expect(config.options, hasLength(4));
    expect(
      backend.requests.single.url.toString(),
      '$serverUrl/api/v1/client/push-config',
    );
  });

  test('a server without push options answers none', () async {
    expect(await backend.api().getPushConfig(), isNull);
  });

  test('push options that are not strings are an unexpected answer', () {
    backend.pushConfig = {
      'provider': 'fcm',
      'options': {'FIREBASE_PROJECT_ID': null},
    };

    expect(
      backend.api().getPushConfig(),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          'The server sent an unexpected answer',
        ),
      ),
    );
  });

  test('a rejected key reading push options is unauthorized', () {
    backend.acceptedKey = null;

    expect(
      backend.api().getPushConfig(),
      throwsA(isA<UnauthorizedException>()),
    );
  });

  test('sets and removes the push target', () async {
    final api = backend.api();

    final client = await api.setPushTarget('fcm', 'token-1');
    expect(client.pushTarget?.provider, 'fcm');
    final put = backend.requests.single;
    expect(put.method, 'PUT');
    expect(put.url.path, '/api/v1/client/push-target');
    expect(put.headers['Content-Type'], startsWith('application/json'));
    expect(jsonDecode(put.body), {'provider': 'fcm', 'token': 'token-1'});

    await api.deletePushTarget();
    expect(backend.requests.last.method, 'DELETE');
    expect(backend.pushTarget, isNull);
  });

  test('an admin device lists devices, makes admins and revokes', () async {
    backend
      ..admin = true
      ..addClient('c-2', 'Tablet')
      ..addClient('c-3', 'Old phone');
    final api = backend.api();

    final devices = await api.listDevices();
    expect(
      [for (final d in devices) d.name],
      ['Pixel 8', 'Tablet', 'Old phone'],
    );
    expect(devices.first.admin, isTrue);
    expect(backend.requests.last.url.path, '/api/v1/client/devices');

    final admin = await api.makeDeviceAdmin('c-2');
    expect(admin.admin, isTrue);
    expect(backend.requests.last.method, 'POST');
    expect(backend.requests.last.url.path, '/api/v1/client/devices/c-2/admin');
    expect(backend.requests.last.body, isEmpty);

    final revoked = await api.revokeDevice('c-3');
    expect(revoked.isRevoked, isTrue);
    expect(backend.requests.last.url.path, '/api/v1/client/devices/c-3/revoke');
  });

  test('device management refuses a device that is not an admin', () {
    expect(
      backend.api().listDevices(),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 403)
            .having(
              (e) => e.message,
              'message',
              'The server answered 403: Not an admin device',
            ),
      ),
    );
  });

  test('an admin device creates a pairing code', () async {
    backend.admin = true;

    final pairing = await backend.api().createPairing('Tablet');

    expect(pairing.name, 'Tablet');
    expect(pairing.code, startsWith('shpc1_'));
    expect(pairing.uri, startsWith('signalhub://pair?server='));
    expect(backend.requests.last.method, 'POST');
    expect(backend.requests.last.url.path, '/api/v1/client/pairings');
    expect(jsonDecode(backend.requests.last.body), {'name': 'Tablet'});
  });

  test('creating a pairing code refuses a device that is not an admin', () {
    expect(
      backend.api().createPairing('Tablet'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
    );
  });

  test('replaces the push preferences', () async {
    final api = backend.api();

    final client = await api.setPushPreferences(
      const PushPreferences(
        enabled: false,
        minimumSeverity: 'HIGH',
        mutedCategories: ['INFO'],
        mutedProducerIds: ['p-2'],
      ),
    );

    final put = backend.requests.single;
    expect(put.method, 'PUT');
    expect(put.url.path, '/api/v1/client/push-preferences');
    expect(jsonDecode(put.body), {
      'enabled': false,
      'minimumSeverity': 'HIGH',
      'mutedCategories': ['INFO'],
      'mutedProducerIds': ['p-2'],
    });
    final stored = client.pushPreferences!;
    expect(stored.enabled, isFalse);
    expect(stored.minimumSeverity, 'HIGH');
    expect(stored.mutedCategories, ['INFO']);
    expect(stored.mutedProducerIds, ['p-2']);
  });

  test('lists events newest first with a limit', () async {
    backend
      ..publish('e-1', 'Older')
      ..publish('e-2', 'Newer');

    final page = await backend.api().listEvents(limit: 1);

    expect(backend.requests.single.url.queryParameters, {'limit': '1'});
    expect(page.nextCursor, isNotNull);
    final event = page.items.single;
    expect(event.id, 'e-2');
    expect(event.title, 'Newer');
    expect(event.producer.name, 'nightly-build');
    expect(event.category, EventCategory.blocked);
    expect(event.severity, EventSeverity.high);
    expect(event.metadata, {'run': 7});
    expect(event.createdAt, DateTime.utc(2026, 9, 25, 12, 3, 0, 123, 456));
  });

  test('passes the cursor back for the next page', () async {
    backend
      ..publish('e-1', 'Oldest')
      ..publish('e-2', 'Middle')
      ..publish('e-3', 'Newest');
    final api = backend.api();

    final first = await api.listEvents(limit: 2);
    final second = await api.listEvents(limit: 2, cursor: first.nextCursor);

    expect(first.items.map((e) => e.id), ['e-3', 'e-2']);
    expect(second.items.map((e) => e.id), ['e-1']);
    expect(second.nextCursor, isNull);
    expect(backend.requests.last.url.queryParameters, {
      'limit': '2',
      'cursor': first.nextCursor,
    });
  });

  test('sends the filter as the listing\'s parameters', () async {
    backend
      ..publish('e-1', 'Read', readAt: '2026-09-25T12:10:00Z')
      ..publish('e-2', 'Other producer', producer: {'id': 'p-2', 'name': 'nas'})
      ..publish('e-3', 'Info', category: 'INFO', severity: 'LOW')
      ..publish('e-4', 'Match');

    final page = await backend.api().listEvents(
      limit: 10,
      filter: const InboxFilter(
        unreadOnly: true,
        producerIds: {'p-1'},
        categories: {EventCategory.blocked, EventCategory.actionRequired},
        severities: {EventSeverity.high},
      ),
    );

    expect(backend.requests.single.url.queryParametersAll, {
      'limit': ['10'],
      'read': ['false'],
      'producerId': ['p-1'],
      'category': ['ACTION_REQUIRED', 'BLOCKED'],
      'severity': ['HIGH'],
    });
    expect(page.items.map((e) => e.id), ['e-4']);
  });

  test('no filter sends no filter parameters', () async {
    await backend.api().listEvents(filter: InboxFilter.none);

    expect(backend.requests.single.url.queryParameters, {'limit': '50'});
  });

  test('reads one event by its ID', () async {
    backend.publish('e-1', 'Build failed', message: '3 tests failed');

    final event = await backend.api().getEvent('e-1');

    expect(backend.requests.single.url.path, '/api/v1/events/e-1');
    expect(
      backend.requests.single.headers['Authorization'],
      'Bearer $clientKey',
    );
    expect(event.title, 'Build failed');
    expect(event.message, '3 tests failed');
  });

  test('an unknown event ID is an EventNotFoundException', () async {
    await expectLater(
      backend.api().getEvent('e-404'),
      throwsA(
        isA<EventNotFoundException>().having(
          (e) => e.statusCode,
          'statusCode',
          404,
        ),
      ),
    );
  });

  test('marks one event read and unread', () async {
    backend.publish('e-1', 'Build failed');
    final api = backend.api();

    final read = await api.markRead('e-1');
    expect(read.isRead, isTrue);
    expect(read.readAt, DateTime.utc(2026, 9, 25, 12, 10));
    expect(backend.requests.last.method, 'PUT');
    expect(backend.requests.last.url.path, '/api/v1/events/e-1/read');
    expect(backend.requests.last.headers['Authorization'], 'Bearer $clientKey');

    final unread = await api.markUnread('e-1');
    expect(unread.isRead, isFalse);
    expect(backend.requests.last.method, 'DELETE');
    expect(backend.requests.last.url.path, '/api/v1/events/e-1/read');
    expect(backend.isRead('e-1'), isFalse);
  });

  test('marks events read through one event and counts unread', () async {
    backend
      ..publish('e-1', 'Oldest')
      ..publish('e-2', 'Middle')
      ..publish('e-3', 'Newest');
    final api = backend.api();
    expect(await api.unreadCount(), 3);
    expect(backend.requests.last.url.path, '/api/v1/events/unread-count');

    expect(await api.markReadThrough('e-2'), 2);

    final post = backend.requests.last;
    expect(post.method, 'POST');
    expect(post.url.path, '/api/v1/events/read');
    expect(post.headers['Content-Type'], startsWith('application/json'));
    expect(jsonDecode(post.body), {'through': 'e-2'});
    expect(await api.unreadCount(), 1);
    expect(backend.isRead('e-3'), isFalse);
  });

  test('marking an unknown event is an EventNotFoundException', () async {
    final api = backend.api();

    await expectLater(
      api.markRead('e-404'),
      throwsA(isA<EventNotFoundException>()),
    );
    await expectLater(
      api.markReadThrough('e-404'),
      throwsA(isA<EventNotFoundException>()),
    );
  });

  test('a rejected key is an UnauthorizedException', () async {
    backend.acceptedKey = null;

    await expectLater(
      backend.api().getClient(),
      throwsA(isA<UnauthorizedException>()),
    );
  });

  test('other errors carry the status and the error title', () async {
    final api = SignalHubApi(
      ServerCredentials.parse(serverUrl, clientKey),
      MockClient(
        (_) async => http.Response(
          '{"title": "Invalid request", "status": 400, "violations": []}',
          400,
        ),
      ),
    );

    await expectLater(
      api.getClient(),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 400)
            .having(
              (e) => e.message,
              'message',
              'The server answered 400: Invalid request',
            ),
      ),
    );
  });

  test('a non-SignalHub error body still gives a message', () async {
    final api = SignalHubApi(
      ServerCredentials.parse(serverUrl, clientKey),
      MockClient((_) async => http.Response('<html>Bad gateway</html>', 502)),
    );

    await expectLater(
      api.getClient(),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          'The server answered 502',
        ),
      ),
    );
  });

  test('an unexpected success body is an ApiException', () async {
    final api = SignalHubApi(
      ServerCredentials.parse(serverUrl, clientKey),
      MockClient((_) async => http.Response('{"id": 42}', 200)),
    );

    await expectLater(api.getClient(), throwsA(isA<ApiException>()));
  });

  test('an unreachable server is an ApiException without a status', () async {
    backend.offline = true;

    await expectLater(
      backend.api().getClient(),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', isNull)
            .having((e) => e.message, 'message', 'Could not reach the server'),
      ),
    );
  });
}
