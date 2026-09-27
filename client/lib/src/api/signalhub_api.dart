import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../connection/server_credentials.dart';
import '../models/client_registration.dart';
import '../models/event.dart';
import '../models/inbox_filter.dart';
import '../models/json.dart';
import '../models/push_config.dart';

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
        ClientRegistration.fromJson(json),
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
