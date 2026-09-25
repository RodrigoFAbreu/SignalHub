import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:signalhub_client/src/api/signalhub_api.dart';
import 'package:signalhub_client/src/connection/server_credentials.dart';
import 'package:signalhub_client/src/push/push_service.dart';

const serverUrl = 'https://signalhub.test';
const clientKey = 'shck1_01a0da2c1f3e7a518d0c6b1f2e3d4c5b_secret';

/// An in-memory stand-in for the backend's client API, answering the way
/// docs/architecture.md describes it.
class FakeBackend {
  final requests = <http.Request>[];
  final events = <Map<String, Object?>>[];

  /// The client key the backend accepts; `null` once revoked.
  String? acceptedKey = clientKey;
  Map<String, Object?>? pushTarget;
  String? pushToken;

  /// When set, every request fails to connect.
  bool offline = false;

  /// When set, requests for older pages (with a cursor) are answered only
  /// once it completes.
  Completer<void>? holdOlderPages;

  late final http.Client client = MockClient(_handle);

  SignalHubApi api([String url = serverUrl, String key = clientKey]) =>
      SignalHubApi(ServerCredentials.parse(url, key), client);

  void publish(String id, String title, {String? message, String? context}) =>
      events.insert(0, {
        'id': id,
        'producer': {'id': 'p-1', 'name': 'nightly-build'},
        'context': context,
        'category': 'BLOCKED',
        'severity': 'HIGH',
        'title': title,
        'message': message,
        'metadata': {'run': 7},
        'occurredAt': null,
        'createdAt': '2026-09-25T12:03:00.123456Z',
      });

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    if (offline) throw http.ClientException('offline', request.url);
    // Servers may sit below a base path behind a reverse proxy.
    final path = request.url.path.substring(request.url.path.indexOf('/api/'));
    // Reading one event needs no credential (docs/architecture.md).
    const eventPath = '/api/v1/events/';
    if (request.method == 'GET' && path.startsWith(eventPath)) {
      final id = path.substring(eventPath.length);
      final event = events.where((e) => e['id'] == id).firstOrNull;
      return event == null
          ? _json(404, {'title': 'Event not found', 'status': 404})
          : _json(200, event);
    }
    if (request.headers['Authorization'] != 'Bearer $acceptedKey') {
      return _json(401, {'title': 'Unauthorized', 'status': 401});
    }
    final route = '${request.method} $path';
    switch (route) {
      case 'GET /api/v1/client':
        return _json(200, _client());
      case 'PUT /api/v1/client/push-target':
        final body = jsonDecode(request.body) as Map<String, Object?>;
        pushToken = body['token'] as String?;
        pushTarget = {
          'provider': body['provider'],
          'updatedAt': '2026-09-25T12:00:00Z',
        };
        return _json(200, _client());
      case 'DELETE /api/v1/client/push-target':
        pushTarget = null;
        pushToken = null;
        return _json(200, _client());
      case 'GET /api/v1/events':
        // The cursor is the position after the previous page: opaque to
        // the app, like the backend's.
        final query = request.url.queryParameters;
        if (query.containsKey('cursor')) await holdOlderPages?.future;
        final limit = int.parse(query['limit'] ?? '50');
        final start = switch (query['cursor']) {
          final cursor? => events.indexWhere((e) => e['id'] == cursor) + 1,
          null => 0,
        };
        final page = events.skip(start).take(limit).toList();
        final more = start + page.length < events.length;
        return _json(200, {
          'items': page,
          'nextCursor': more ? page.last['id'] : null,
        });
    }
    return _json(404, {'title': 'Not Found', 'status': 404});
  }

  Map<String, Object?> _client() => {
    'id': '01a0da2c-1f3e-7a51-8d0c-6b1f2e3d4c5b',
    'name': 'Pixel 8',
    'createdAt': '2026-09-25T18:02:11.108811Z',
    'revokedAt': null,
    'pushTarget': pushTarget,
  };

  static http.Response _json(int status, Object body) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
}

class FakePushService implements PushService {
  bool permitted = true;
  String? token = 'device-token-1';
  bool tokenDeleted = false;
  final refreshes = StreamController<String>.broadcast();
  final received = StreamController<PushNotice>();

  @override
  String get provider => 'fake';

  @override
  Future<bool> requestPermission() async => permitted;

  @override
  Future<String?> getToken() async => token;

  @override
  Stream<String> get tokenRefreshes => refreshes.stream;

  @override
  Stream<PushNotice> get notices => received.stream;

  @override
  Future<void> deleteToken() async {
    tokenDeleted = true;
    token = null;
  }
}

class InMemoryCredentialsStore implements CredentialsStore {
  ServerCredentials? saved;

  @override
  Future<ServerCredentials?> load() async => saved;

  @override
  Future<void> save(ServerCredentials credentials) async => saved = credentials;

  @override
  Future<void> clear() async => saved = null;
}
