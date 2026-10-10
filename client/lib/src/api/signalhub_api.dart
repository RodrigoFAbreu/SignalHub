import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../connection/server_credentials.dart';
import '../models/client_registration.dart';
import '../models/event.dart';
import '../models/inbox_filter.dart';
import '../models/json.dart';
import '../models/producers.dart';
import '../models/push_config.dart';
import '../models/users.dart';

/// A request to the backend failed.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  /// For the owner: what went wrong, without credentials.
  final String message;

  /// The HTTP status, or `null` when no response arrived.
  final int? statusCode;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// The backend rejected the client key: it is wrong, or the client was
/// revoked. The backend deliberately does not say which.
class UnauthorizedException extends ApiException {
  const UnauthorizedException()
    : super('The server did not accept this client key', statusCode: 401);
}

/// The server has no event with the requested ID.
class EventNotFoundException extends ApiException {
  const EventNotFoundException()
    : super('This event does not exist on the server', statusCode: 404);
}

/// The server did not accept a pairing code: it is expired, already used or
/// unknown. The backend deliberately does not say which.
class PairingRejectedException extends ApiException {
  const PairingRejectedException()
    : super(
        'This pairing code has expired or was already used. '
        'Ask for a new one.',
        statusCode: 401,
      );
}

/// A client a pairing code registered, and its client key.
class PairedClient {
  const PairedClient(this.registration, this.clientKey);

  final ClientRegistration registration;

  /// Returned only once, by the redemption.
  final String clientKey;
}

/// The client side of the backend's HTTP API, authenticated with a client
/// key. It uses only the public, documented contract.
class SignalHubApi {
  SignalHubApi(this._credentials, this._http);

  static const timeout = Duration(seconds: 15);

  final ServerCredentials _credentials;
  final http.Client _http;

  /// `POST /api/v1/pairing`: redeems a one-time pairing code at [serverUrl],
  /// which registers a new client, and returns it with its client key. Throws
  /// [PairingRejectedException] for an expired, used or unknown code.
  static Future<PairedClient> redeemPairing(
    http.Client client,
    String serverUrl,
    String code,
  ) async {
    final Map<String, Object?> body;
    try {
      body = await _request(
        client,
        'POST',
        Uri.parse('$serverUrl/api/v1/pairing'),
        bearer: code,
      );
    } on UnauthorizedException {
      throw const PairingRejectedException();
    }
    return _read(
      body,
      (json) => PairedClient(
        ClientRegistration.fromJson(json.object('client')),
        json.string('clientKey'),
      ),
    );
  }

  /// `GET /api/v1/client`: this installation's registration.
  Future<ClientRegistration> getClient() async =>
      _read(await _send('GET', 'api/v1/client'), ClientRegistration.fromJson);

  /// `GET /api/v1/client/push-config`: the options to set up push with the
  /// server's provider, or `null` when the operator configured none (`404`).
  Future<PushConfig?> getPushConfig() async {
    final Map<String, Object?> body;
    try {
      body = await _send('GET', 'api/v1/client/push-config');
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
    return _read(body, PushConfig.fromJson);
  }

  /// `PUT /api/v1/client/push-target`: where pushes for this client go.
  Future<ClientRegistration> setPushTarget(
    String provider,
    String token,
  ) async => _read(
    await _send(
      'PUT',
      'api/v1/client/push-target',
      body: {'provider': provider, 'token': token},
    ),
    ClientRegistration.fromJson,
  );

  /// `DELETE /api/v1/client/push-target`. Idempotent.
  Future<void> deletePushTarget() async {
    await _send('DELETE', 'api/v1/client/push-target');
  }

  /// `PUT /api/v1/client/push-preferences`: replaces which events are pushed
  /// to this client; answers the registration with the stored preferences.
  Future<ClientRegistration> setPushPreferences(
    PushPreferences preferences,
  ) async => _read(
    await _send(
      'PUT',
      'api/v1/client/push-preferences',
      body: preferences.toJson(),
    ),
    ClientRegistration.fromJson,
  );

  /// `GET /api/v1/client/devices`: every client of the owner, revoked or
  /// not, oldest first. Only an admin device's key is accepted: any other
  /// gets `403`, and a server released before device management `404`.
  Future<List<ManagedDevice>> listDevices() async => _read(
    await _send('GET', 'api/v1/client/devices'),
    (json) => json
        .list('items')
        .map((item) => ManagedDevice.fromJson(asObject(item, 'items[]')))
        .toList(growable: false),
  );

  /// `PATCH /api/v1/client/devices/{id}`: renames a client (a mod their own,
  /// an admin any that is not an admin's). `409` for a revoked client or an
  /// admin's device, `403` for a basic user.
  Future<ManagedDevice> renameDevice(String id, String name) async => _read(
    await _send(
      'PATCH',
      'api/v1/client/devices/${Uri.encodeComponent(id)}',
      body: {'name': name},
    ),
    ManagedDevice.fromJson,
  );

  /// `POST /api/v1/client/devices/{id}/revoke`: revokes a client. Idempotent;
  /// `409` for an admin's device or a mod's last active device.
  Future<ManagedDevice> revokeDevice(String id) => _changeDevice(id, 'revoke');

  /// `DELETE /api/v1/client/devices/{id}`: deletes a revoked client, `204`.
  /// `409` for an active client, `404` for one that does not exist (deleted
  /// already); a server released before deleting devices answers `404` or
  /// `405` for a device it lists.
  Future<void> deleteDevice(String id) async {
    await _send('DELETE', 'api/v1/client/devices/${Uri.encodeComponent(id)}');
  }

  Future<ManagedDevice> _changeDevice(String id, String action) async => _read(
    await _send(
      'POST',
      'api/v1/client/devices/${Uri.encodeComponent(id)}/$action',
    ),
    ManagedDevice.fromJson,
  );

  /// `POST /api/v1/client/pairings`: a one-time pairing code for a new
  /// device named [name], for this device's own user or, from an admin's
  /// device, for [userId]. `403` for a basic user (or a mod naming another
  /// user), and a server released before pairing from a device `404`.
  Future<DevicePairing> createPairing(String name, {String? userId}) async =>
      _read(
        await _send(
          'POST',
          'api/v1/client/pairings',
          body: {'name': name, 'userId': ?userId},
        ),
        DevicePairing.fromJson,
      );

  /// `GET /api/v1/client/pairings/{id}`: whether a pairing code this device
  /// created was used, and by which device. `404` for any other pairing, and
  /// `403` for a device that is not an admin; a server released before this
  /// answers `404` or `405`.
  Future<PairingStatus> getPairingStatus(String id) async => _read(
    await _send('GET', 'api/v1/client/pairings/${Uri.encodeComponent(id)}'),
    PairingStatus.fromJson,
  );

  /// `GET /api/v1/client/server`: the release the server runs.
  Future<ServerInfo> getServer() async =>
      _read(await _send('GET', 'api/v1/client/server'), ServerInfo.fromJson);

  /// `GET /api/v1/client/visible-producers`: the producers this user may
  /// see, by name.
  Future<List<VisibleProducer>> listVisibleProducers() async => _read(
    await _send('GET', 'api/v1/client/visible-producers'),
    (json) => _items(json, VisibleProducer.fromJson),
  );

  /// `PUT /api/v1/client/visible-producers/{id}/subscription`. Idempotent;
  /// `404` for a producer this user does not see.
  Future<VisibleProducer> subscribe(String producerId) =>
      _subscription('PUT', producerId);

  /// `DELETE /api/v1/client/visible-producers/{id}/subscription`.
  Future<VisibleProducer> unsubscribe(String producerId) =>
      _subscription('DELETE', producerId);

  Future<VisibleProducer> _subscription(String method, String id) async =>
      _read(
        await _send(
          method,
          'api/v1/client/visible-producers/${Uri.encodeComponent(id)}'
          '/subscription',
        ),
        VisibleProducer.fromJson,
      );

  /// `GET /api/v1/client/producers`: the producers this user owns.
  Future<List<OwnProducer>> listOwnProducers() async => _read(
    await _send('GET', 'api/v1/client/producers'),
    (json) => _items(json, OwnProducer.fromJson),
  );

  /// `GET /api/v1/client/producers/{id}`. `404` for a producer this user
  /// does not own, whatever it is.
  Future<OwnProducer> getOwnProducer(String id) async =>
      _read(await _send('GET', _producerPath(id)), OwnProducer.fromJson);

  /// `POST /api/v1/client/producers`: registers a producer this user owns
  /// and issues its first key, which is in the answer only. `409` for a name
  /// taken (even by a private producer of someone else's), `400` for a name
  /// the server does not allow.
  Future<IssuedProducerKey> createProducer(
    String name, {
    ProducerVisibility visibility = ProducerVisibility.private,
  }) async => _read(
    await _send(
      'POST',
      'api/v1/client/producers',
      body: {'name': name, 'visibility': visibility.wireName},
    ),
    IssuedProducerKey.fromJson,
  );

  /// `PATCH /api/v1/client/producers/{id}`: renames it and/or sets who may
  /// see it; at least one.
  Future<OwnProducer> updateProducer(
    String id, {
    String? name,
    ProducerVisibility? visibility,
  }) async => _read(
    await _send(
      'PATCH',
      _producerPath(id),
      body: {'name': ?name, 'visibility': ?visibility?.wireName},
    ),
    OwnProducer.fromJson,
  );

  /// `POST /api/v1/client/producers/{id}/keys`: an additional key, in the
  /// answer only.
  Future<IssuedProducerKey> issueProducerKey(String id) async => _read(
    await _send('POST', '${_producerPath(id)}/keys'),
    IssuedProducerKey.fromJson,
  );

  /// `POST /api/v1/client/producers/{id}/keys/{keyId}/revoke`: for good.
  Future<OwnProducer> revokeProducerKey(String id, String keyId) async => _read(
    await _send(
      'POST',
      '${_producerPath(id)}/keys/${Uri.encodeComponent(keyId)}/revoke',
    ),
    OwnProducer.fromJson,
  );

  /// `POST /api/v1/client/producers/{id}/disable`: its keys stop working;
  /// its events stay.
  Future<OwnProducer> disableProducer(String id) =>
      _producerAction(id, 'disable');

  /// `POST /api/v1/client/producers/{id}/enable`. `409` for a producer the
  /// host disabled.
  Future<OwnProducer> enableProducer(String id) =>
      _producerAction(id, 'enable');

  Future<OwnProducer> _producerAction(String id, String action) async => _read(
    await _send('POST', '${_producerPath(id)}/$action'),
    OwnProducer.fromJson,
  );

  /// `PUT /api/v1/client/producers/{id}/allowed-users/{userId}`.
  Future<OwnProducer> allowUser(String id, String userId) =>
      _allowedUser('PUT', id, userId);

  /// `DELETE /api/v1/client/producers/{id}/allowed-users/{userId}`: also
  /// ends that user's subscription to a private producer.
  Future<OwnProducer> disallowUser(String id, String userId) =>
      _allowedUser('DELETE', id, userId);

  Future<OwnProducer> _allowedUser(
    String method,
    String id,
    String userId,
  ) async => _read(
    await _send(
      method,
      '${_producerPath(id)}/allowed-users/${Uri.encodeComponent(userId)}',
    ),
    OwnProducer.fromJson,
  );

  static String _producerPath(String id) =>
      'api/v1/client/producers/${Uri.encodeComponent(id)}';

  /// `GET /api/v1/client/users`: the people on the server who are not
  /// removed. Names only, unless the key is an admin's.
  Future<List<Person>> listPeople() async => _read(
    await _send('GET', 'api/v1/client/users'),
    (json) => _items(json, Person.fromJson),
  );

  /// `GET /api/v1/client/users/{id}/producers`: admin only. `404` for an
  /// unknown or removed user.
  Future<List<PersonProducer>> listPersonProducers(String userId) async =>
      _read(
        await _send(
          'GET',
          'api/v1/client/users/${Uri.encodeComponent(userId)}/producers',
        ),
        (json) => _items(json, PersonProducer.fromJson),
      );

  /// `POST /api/v1/client/users`: admin only. Invites a user and creates the
  /// pairing code of their first device. `409` for a name taken.
  Future<({UserRef user, DevicePairing pairing})> inviteUser(
    String name, {
    required UserRole role,
    String? deviceName,
  }) async => _read(
    await _send(
      'POST',
      'api/v1/client/users',
      body: {'name': name, 'role': role.wireName, 'deviceName': ?deviceName},
    ),
    (json) => (
      user: UserRef.fromJson(json.object('user')),
      pairing: DevicePairing.fromJson(json.object('pairing')),
    ),
  );

  /// `PATCH /api/v1/client/users/{id}`: admin only. Sets the role of a user
  /// who is not an admin to basic or mod.
  Future<UserRef> setUserRole(String userId, UserRole role) async => _read(
    await _send(
      'PATCH',
      'api/v1/client/users/${Uri.encodeComponent(userId)}',
      body: {'role': role.wireName},
    ),
    UserRef.fromJson,
  );

  static List<T> _items<T>(
    Map<String, Object?> json,
    T Function(Map<String, Object?>) read,
  ) => json
      .list('items')
      .map((item) => read(asObject(item, 'items[]')))
      .toList(growable: false);

  /// `GET /api/v1/events`: one page of events matching [filter], newest
  /// first. Pass the previous page's [EventPage.nextCursor] as [cursor], with
  /// the same filter, for the next one.
  Future<EventPage> listEvents({
    int limit = 50,
    String? cursor,
    InboxFilter filter = InboxFilter.none,
  }) async {
    final query = Uri(
      queryParameters: {
        'limit': '$limit',
        'cursor': ?cursor,
        ...filter.queryParameters,
      },
    ).query;
    return _read(
      await _send('GET', 'api/v1/events?$query'),
      EventPage.fromJson,
    );
  }

  /// `GET /api/v1/events/{id}`: one event. Throws [EventNotFoundException]
  /// for an ID the server does not know.
  Future<Event> getEvent(String id) async => _read(
    await _eventRequest('GET', 'api/v1/events/${Uri.encodeComponent(id)}'),
    Event.fromJson,
  );

  /// `PUT /api/v1/events/{id}/read`: marks one event read, for every client
  /// of the owner. Idempotent; answers the event.
  Future<Event> markRead(String id) => _setRead('PUT', id);

  /// `DELETE /api/v1/events/{id}/read`: marks one event unread again.
  Future<Event> markUnread(String id) => _setRead('DELETE', id);

  /// `POST /api/v1/events/read`: marks read every unread event at or before
  /// [throughId] in listing order, and answers how many changed. Events
  /// newer than [throughId] stay unread.
  Future<int> markReadThrough(String throughId) async {
    final body = await _eventRequest(
      'POST',
      'api/v1/events/read',
      body: {'through': throughId},
    );
    return _read(body, (json) => json.integer('marked'));
  }

  /// `GET /api/v1/events/unread-count`: unread events, on the whole server.
  Future<int> unreadCount() async => _read(
    await _send('GET', 'api/v1/events/unread-count'),
    (json) => json.integer('unread'),
  );

  Future<Event> _setRead(String method, String id) async => _read(
    await _eventRequest(
      method,
      'api/v1/events/${Uri.encodeComponent(id)}/read',
    ),
    Event.fromJson,
  );

  /// A request about one event: `404` means the server does not know it.
  Future<Map<String, Object?>> _eventRequest(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    try {
      return await _send(method, path, body: body);
    } on ApiException catch (e) {
      if (e.statusCode == 404) throw const EventNotFoundException();
      rethrow;
    }
  }

  Future<Map<String, Object?>> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) => _request(
    _http,
    method,
    _credentials.endpoint(path),
    bearer: _credentials.clientKey,
    body: body,
  );

  static Future<Map<String, Object?>> _request(
    http.Client client,
    String method,
    Uri url, {
    required String bearer,
    Map<String, Object?>? body,
  }) async {
    final request = http.Request(method, url)
      ..headers['Authorization'] = 'Bearer $bearer'
      ..headers['Accept'] = 'application/json';
    if (body != null) {
      request
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);
    }
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await client.send(request).timeout(timeout),
      ).timeout(timeout);
    } on TimeoutException {
      throw const ApiException('The server did not answer in time');
    } on http.ClientException {
      throw const ApiException('Could not reach the server');
    }
    return _decode(response);
  }

  static Map<String, Object?> _decode(http.Response response) {
    final status = response.statusCode;
    if (status == 401) throw const UnauthorizedException();
    if (status < 200 || status >= 300) {
      throw ApiException(_errorTitle(response), statusCode: status);
    }
    if (status == 204) return const {};
    try {
      return asObject(jsonDecode(response.body), 'response');
    } on FormatException {
      throw ApiException(
        'The server sent an unexpected answer',
        statusCode: status,
      );
    }
  }

  /// Maps a body that does not match the documented contract to an
  /// [ApiException], like any other failed request.
  static T _read<T>(
    Map<String, Object?> body,
    T Function(Map<String, Object?>) fromJson,
  ) {
    try {
      return fromJson(body);
    } on FormatException catch (e) {
      debugPrint('Unexpected response: ${e.message}');
      throw const ApiException('The server sent an unexpected answer');
    }
  }

  /// Error bodies are `{"title", "status", "violations"}`; a proxy in front of
  /// the backend may answer with anything else.
  static String _errorTitle(http.Response response) {
    try {
      final title = asObject(
        jsonDecode(response.body),
        'error',
      ).optionalString('title');
      if (title != null && title.isNotEmpty) {
        return 'The server answered ${response.statusCode}: $title';
      }
    } on FormatException {
      // Not a SignalHub error body.
    }
    return 'The server answered ${response.statusCode}';
  }
}
