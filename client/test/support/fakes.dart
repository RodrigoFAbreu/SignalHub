import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:signalhub_client/src/api/signalhub_api.dart';
import 'package:signalhub_client/src/connection/server_credentials.dart';
import 'package:signalhub_client/src/models/push_config.dart';
import 'package:signalhub_client/src/push/push_service.dart';

const serverUrl = 'https://signalhub.test';
const clientKey = 'shck1_01a0da2c1f3e7a518d0c6b1f2e3d4c5b_secret';
const pairingCode = 'shpc1_Zt1vQ3x9rB2mKc8wYp4aLd';
const pairedClientKey = 'shck1_01a0da2c1f3e7a518d0c6b1f2e3d4c5c_paired';

/// The pairing URI of [pairingCode] for [serverUrl], as the backend makes it.
final pairingUri = Uri(
  scheme: 'signalhub',
  host: 'pair',
  queryParameters: {'server': serverUrl, 'code': pairingCode},
).toString();

/// An in-memory stand-in for the backend's client API, answering the way
/// docs/architecture.md describes it.
class FakeBackend {
  final requests = <http.Request>[];
  final events = <Map<String, Object?>>[];

  /// The client key the backend accepts; `null` once revoked.
  String? acceptedKey = clientKey;
  Map<String, Object?>? pushTarget;
  String? pushToken;

  /// The stored push preferences; `null` for a server released before they
  /// existed, which leaves them out of the client and has no path for them.
  Map<String, Object?>? pushPreferences = defaultPushPreferences;

  static const defaultPushPreferences = <String, Object?>{
    'enabled': true,
    'minimumSeverity': 'LOW',
    'mutedCategories': <String>[],
    'mutedProducerIds': <String>[],
  };

  /// Whether this client is an admin device; `null` for a server released
  /// before admin devices, which leaves the field out.
  bool? admin = false;

  /// Whether the server has the device endpoints of admin devices; a server
  /// released before them answers `404`.
  bool deviceEndpoints = true;

  /// The owner's other clients, as `GET /api/v1/client/devices` lists them
  /// after this one.
  final otherClients = <Map<String, Object?>>[];

  void addClient(
    String id,
    String name, {
    bool admin = false,
    bool revoked = false,
  }) => otherClients.add({
    'id': id,
    'name': name,
    'admin': admin,
    'createdAt': '2026-09-26T08:00:00Z',
    'revokedAt': revoked ? '2026-09-26T09:00:00Z' : null,
    'pushTarget': null,
    'pushPreferences': defaultPushPreferences,
    'pushStatus': null,
  });

  /// How a server released before deleting devices answers a delete: `404`
  /// (no such route) or `405`; `null` for a server that deletes them.
  int? noDeviceDeletion;

  /// Whether the server lets an admin device create pairing codes; a server
  /// released before that answers `404`.
  bool devicePairings = true;

  /// The public address the server builds pairing URIs from; `null` when the
  /// operator configured none, so pairings have no URI.
  String? publicUrl = serverUrl;

  /// When pairing codes created from a device expire.
  DateTime pairingExpiresAt = DateTime.utc(2026, 9, 27, 12, 10);

  /// The names of the devices pairing codes were created for from a device.
  final devicePairingNames = <String>[];

  /// Whether pairings from a device carry the ID their status is asked by; a
  /// server released before it could say whether a code was used leaves it
  /// out.
  bool pairingIds = true;

  /// How a server without the status of a pairing answers for it: `404` or
  /// `405`; `null` for a server that has it.
  int? noPairingStatus;

  /// The pairings from a device a device used, by pairing ID: the client
  /// each registered.
  final _pairingsUsed = <String, Map<String, Object?>>{};

  /// A device named [name] uses the last pairing code created from a device:
  /// it is registered, and listed with the owner's other clients.
  void usePairing(String name) {
    final index = devicePairingNames.length - 1;
    pairingCodes.remove(_devicePairingCode(index));
    final id = 'paired-$index';
    addClient(id, name);
    _pairingsUsed[_devicePairingId(index)] = otherClients.last;
  }

  /// How often the status of a pairing was asked for.
  int get pairingStatusRequests => requests
      .where(
        (r) =>
            r.method == 'GET' &&
            r.url.path.contains('/api/v1/client/pairings/'),
      )
      .length;

  /// The push client options the server serves; `null` when the operator
  /// configured none.
  Map<String, Object?>? pushConfig;

  /// Pairing codes not redeemed yet. Redeeming one registers a client with
  /// [pairedClientKey], which the backend then accepts.
  final pairingCodes = <String>{};

  /// Whether the listing knows the `read` filter; a server released before
  /// it ignores the parameter, as it ignores every unknown one.
  bool readFilter = true;

  /// When set, every request fails to connect.
  bool offline = false;

  /// When set, requests for older pages (with a cursor) are answered only
  /// once it completes.
  Completer<void>? holdOlderPages;

  late final http.Client client = MockClient(_handle);

  SignalHubApi api([String url = serverUrl, String key = clientKey]) =>
      SignalHubApi(ServerCredentials.parse(url, key), client);

  Future<PairedClient> redeemPairing(String url, String code) =>
      SignalHubApi.redeemPairing(client, url, code);

  void publish(
    String id,
    String title, {
    String? message,
    String? context,
    String? readAt,
    String? link,
    String category = 'BLOCKED',
    String severity = 'HIGH',
    Map<String, Object?> producer = const {
      'id': 'p-1',
      'name': 'nightly-build',
    },
  }) => events.insert(0, {
    'id': id,
    'producer': producer,
    'context': context,
    'category': category,
    'severity': severity,
    'title': title,
    'message': message,
    'metadata': {'run': 7},
    'link': link,
    'occurredAt': null,
    'createdAt': '2026-09-25T12:03:00.123456Z',
    'readAt': readAt,
  });

  /// Whether the event with [id] is read on the server.
  bool isRead(String id) =>
      events.firstWhere((e) => e['id'] == id)['readAt'] != null;

  int get _unread => events.where((e) => e['readAt'] == null).length;

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    if (offline) throw http.ClientException('offline', request.url);
    // Servers may sit below a base path behind a reverse proxy.
    final path = request.url.path.substring(request.url.path.indexOf('/api/'));
    if ('${request.method} $path' == 'POST /api/v1/pairing') {
      final code = request.headers['Authorization']?.replaceFirst(
        'Bearer ',
        '',
      );
      if (!pairingCodes.remove(code)) {
        return _json(401, {'title': 'Unauthorized', 'status': 401});
      }
      acceptedKey = pairedClientKey;
      // The backend's IssuedClientKey: the client nested beside its key.
      return _json(201, {'client': _client(), 'clientKey': pairedClientKey});
    }
    if (request.headers['Authorization'] != 'Bearer $acceptedKey') {
      return _json(401, {'title': 'Unauthorized', 'status': 401});
    }
    final eventId = RegExp(r'^/api/v1/events/([^/]+)$')
        .firstMatch(path)
        ?.group(1);
    if (request.method == 'GET' &&
        eventId != null &&
        eventId != 'unread-count') {
      final event = _event(eventId);
      return event == null ? _eventNotFound() : _json(200, event);
    }
    final readId = RegExp(r'^/api/v1/events/([^/]+)/read$')
        .firstMatch(path)
        ?.group(1);
    if (readId != null) {
      final event = _event(readId);
      if (event == null) return _eventNotFound();
      switch (request.method) {
        case 'PUT':
          event['readAt'] ??= '2026-09-25T12:10:00Z';
        case 'DELETE':
          event['readAt'] = null;
        default:
          return _json(405, {'title': 'Method Not Allowed', 'status': 405});
      }
      return _json(200, event);
    }
    if (path.startsWith('/api/v1/client/devices') && deviceEndpoints) {
      return _devices(request.method, path);
    }
    if ('${request.method} $path' == 'POST /api/v1/client/pairings' &&
        devicePairings) {
      return _createPairing(request);
    }
    final statusId = RegExp(r'^/api/v1/client/pairings/([^/]+)$')
        .firstMatch(path)
        ?.group(1);
    if (request.method == 'GET' && statusId != null) {
      return _pairingStatus(statusId);
    }
    final route = '${request.method} $path';
    switch (route) {
      case 'GET /api/v1/events/unread-count':
        return _json(200, {'unread': _unread});
      case 'POST /api/v1/events/read':
        final body = jsonDecode(request.body) as Map<String, Object?>;
        final through = events.indexWhere((e) => e['id'] == body['through']);
        if (through < 0) return _eventNotFound();
        // Newest first: the event and everything after it are older.
        var marked = 0;
        for (final event in events.skip(through)) {
          if (event['readAt'] == null) {
            event['readAt'] = '2026-09-25T12:10:00Z';
            marked++;
          }
        }
        return _json(200, {'marked': marked});
      case 'GET /api/v1/client':
        return _json(200, _client());
      case 'GET /api/v1/client/push-config' when pushConfig != null:
        return _json(200, pushConfig!);
      case 'PUT /api/v1/client/push-target':
        final body = jsonDecode(request.body) as Map<String, Object?>;
        pushToken = body['token'] as String?;
        pushTarget = {
          'provider': body['provider'],
          'updatedAt': '2026-09-25T12:00:00Z',
        };
        return _json(200, _client());
      case 'PUT /api/v1/client/push-preferences' when pushPreferences != null:
        final body = jsonDecode(request.body) as Map<String, Object?>;
        // Replace, not patch: an absent field takes its default. Lists come
        // back sorted without duplicates.
        List<String> sorted(Object? list) =>
            ((list as List<Object?>?) ?? const [])
                .cast<String>()
                .toSet()
                .toList()
              ..sort();
        pushPreferences = {
          'enabled': body['enabled'] ?? true,
          'minimumSeverity': body['minimumSeverity'] ?? 'LOW',
          'mutedCategories': sorted(body['mutedCategories']),
          'mutedProducerIds': sorted(body['mutedProducerIds']),
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
        final matching = events.skip(start).where(_matches(request.url));
        final page = matching.take(limit).toList();
        final more = matching.length > page.length;
        return _json(200, {
          'items': page,
          'nextCursor': more ? page.last['id'] : null,
        });
    }
    return _json(404, {'title': 'Not Found', 'status': 404});
  }

  /// Device management: only an admin device's key is accepted, nothing can
  /// be done to an active admin, and only revoked devices can be deleted.
  http.Response _devices(String method, String path) {
    if (admin != true) {
      return _json(403, {'title': 'Not an admin device', 'status': 403});
    }
    final all = [_client(), ...otherClients];
    if ('$method $path' == 'GET /api/v1/client/devices') {
      return _json(200, {'items': all});
    }
    final deleted = RegExp(r'^/api/v1/client/devices/([^/]+)$')
        .firstMatch(path)
        ?.group(1);
    if (method == 'DELETE' && deleted != null) {
      if (noDeviceDeletion case final status?) {
        final title = status == 405 ? 'Method Not Allowed' : 'Not Found';
        return _json(status, {'title': title, 'status': status});
      }
      final target = all.where((c) => c['id'] == deleted).firstOrNull;
      if (target == null) {
        return _json(404, {'title': 'Not found', 'status': 404});
      }
      if (target['revokedAt'] == null) {
        return _json(409, {'title': 'Client is not revoked', 'status': 409});
      }
      otherClients.remove(target);
      return http.Response('', 204);
    }
    final match = RegExp(r'^/api/v1/client/devices/([^/]+)/(admin|revoke)$')
        .firstMatch(path);
    final target = all.where((c) => c['id'] == match?.group(1)).firstOrNull;
    if (method != 'POST' || target == null) {
      return _json(404, {'title': 'Not Found', 'status': 404});
    }
    final other = otherClients.contains(target);
    if (match!.group(2) == 'admin') {
      if (target['revokedAt'] != null) {
        return _json(409, {'title': 'Client is revoked', 'status': 409});
      }
      if (other) target['admin'] = true;
    } else {
      if (target['admin'] == true) {
        return _json(409, {
          'title': 'Client is an admin device',
          'status': 409,
        });
      }
      if (other) target['revokedAt'] ??= '2026-09-27T09:00:00Z';
    }
    return _json(200, target);
  }

  /// A pairing code from an admin device, for a device that is never an
  /// admin; it redeems like one from the operator.
  http.Response _createPairing(http.Request request) {
    if (admin != true) {
      return _json(403, {'title': 'Not an admin device', 'status': 403});
    }
    final name = (jsonDecode(request.body) as Map<String, Object?>)['name'];
    if (name is! String || name.trim().isEmpty) {
      return _json(400, {'title': 'Bad Request', 'status': 400});
    }
    final index = devicePairingNames.length;
    final code = _devicePairingCode(index);
    devicePairingNames.add(name);
    pairingCodes.add(code);
    return _json(201, {
      if (pairingIds) 'id': _devicePairingId(index),
      'name': name,
      'admin': false,
      'code': code,
      'expiresAt': pairingExpiresAt.toIso8601String(),
      'uri': publicUrl == null
          ? null
          : Uri(
              scheme: 'signalhub',
              host: 'pair',
              queryParameters: {'server': publicUrl, 'code': code},
            ).toString(),
    });
  }

  static String _devicePairingCode(int index) =>
      'shpc1_fromDevice${index}xxxxxxx';

  static String _devicePairingId(int index) => 'pairing-$index';

  /// Whether a pairing from a device was used, and by which device: only an
  /// admin device's key is accepted. The fake has no clock, so a code not
  /// used is pending.
  http.Response _pairingStatus(String id) {
    if (noPairingStatus case final status?) {
      final title = status == 405 ? 'Method Not Allowed' : 'Not Found';
      return _json(status, {'title': title, 'status': status});
    }
    if (admin != true) {
      return _json(403, {'title': 'Not an admin device', 'status': 403});
    }
    final index = int.tryParse(id.replaceFirst('pairing-', '')) ?? -1;
    if (!id.startsWith('pairing-') ||
        index < 0 ||
        index >= devicePairingNames.length) {
      return _json(404, {'title': 'Pairing not found', 'status': 404});
    }
    final used = _pairingsUsed[id];
    return _json(200, {
      'id': id,
      'state': used == null ? 'PENDING' : 'REDEEMED',
      'expiresAt': pairingExpiresAt.toIso8601String(),
      'redeemedAt': used == null ? null : '2026-09-27T12:02:00Z',
      'client': used == null ? null : {'id': used['id'], 'name': used['name']},
    });
  }

  /// The listing's filters: values of one parameter are alternatives, and
  /// every parameter must match.
  bool Function(Map<String, Object?>) _matches(Uri url) {
    final query = url.queryParametersAll;
    bool within(String parameter, Object? value) =>
        !query.containsKey(parameter) || query[parameter]!.contains(value);
    final read = readFilter ? query['read']?.single : null;
    return (event) =>
        within('producerId', (event['producer'] as Map)['id']) &&
        within('category', event['category']) &&
        within('severity', event['severity']) &&
        (read == null || (event['readAt'] != null) == (read == 'true'));
  }

  Map<String, Object?>? _event(String id) =>
      events.where((e) => e['id'] == id).firstOrNull;

  static http.Response _eventNotFound() =>
      _json(404, {'title': 'Event not found', 'status': 404});

  Map<String, Object?> _client() => {
    'id': '01a0da2c-1f3e-7a51-8d0c-6b1f2e3d4c5b',
    'name': 'Pixel 8',
    'admin': ?admin,
    'createdAt': '2026-09-25T18:02:11.108811Z',
    'revokedAt': null,
    'pushTarget': pushTarget,
    'pushPreferences': ?pushPreferences,
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

/// Push options a server serves, in the shape of the backend's FCM options.
const servedPushConfig = <String, Object?>{
  'provider': 'fcm',
  'options': {
    'FIREBASE_PROJECT_ID': 'owner-project',
    'FIREBASE_MESSAGING_SENDER_ID': '1234',
    'FIREBASE_ANDROID_API_KEY': 'android-key',
    'FIREBASE_ANDROID_APP_ID': '1:1234:android:ab',
  },
};

/// Starts a [FakePushService] from served options, standing in for the
/// provider's own start; with [accepts] unset it refuses them, as a provider
/// refuses options that do not fit it.
class FakeServedPushStarter {
  final started = <PushConfig>[];
  final push = FakePushService();
  bool accepts = true;

  Future<PushService?> call(PushConfig served) async {
    started.add(served);
    return accepts ? push : null;
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
