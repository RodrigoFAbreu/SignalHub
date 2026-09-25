import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:signalhub_client/src/api/signalhub_api.dart';
import 'package:signalhub_client/src/connection/server_credentials.dart';
import 'package:signalhub_client/src/models/event.dart';

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

  test('keeps a base path, for servers behind a reverse proxy', () async {
    await backend.api('https://example.org/signalhub/').getClient();

    expect(
      backend.requests.single.url.toString(),
      'https://example.org/signalhub/api/v1/client',
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

  test('reads one event by its ID', () async {
    backend.publish('e-1', 'Build failed', message: '3 tests failed');

    final event = await backend.api().getEvent('e-1');

    expect(backend.requests.single.url.path, '/api/v1/events/e-1');
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
