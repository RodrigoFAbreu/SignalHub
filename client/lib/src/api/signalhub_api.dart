import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../connection/server_credentials.dart';
import '../models/client_registration.dart';
import '../models/event.dart';
import '../models/json.dart';

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

/// The client side of the backend's HTTP API, authenticated with a client
/// key. It uses only the public, documented contract.
class SignalHubApi {
  SignalHubApi(this._credentials, this._http);

  static const timeout = Duration(seconds: 15);

  final ServerCredentials _credentials;
  final http.Client _http;

  /// `GET /api/v1/client`: this installation's registration.
  Future<ClientRegistration> getClient() async =>
      _read(await _send('GET', 'api/v1/client'), ClientRegistration.fromJson);

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

  /// `GET /api/v1/events`: one page of events, newest first. Pass the
  /// previous page's [EventPage.nextCursor] as [cursor] for the next one.
  Future<EventPage> listEvents({int limit = 50, String? cursor}) async {
    final query = Uri(queryParameters: {'limit': '$limit', 'cursor': ?cursor})
        .query;
    return _read(
      await _send('GET', 'api/v1/events?$query'),
      EventPage.fromJson,
    );
  }

  /// `GET /api/v1/events/{id}`: one event. Throws [EventNotFoundException]
  /// for an ID the server does not know.
  Future<Event> getEvent(String id) async {
    final Map<String, Object?> body;
    try {
      body = await _send('GET', 'api/v1/events/${Uri.encodeComponent(id)}');
    } on ApiException catch (e) {
      if (e.statusCode == 404) throw const EventNotFoundException();
      rethrow;
    }
    return _read(body, Event.fromJson);
  }

  Future<Map<String, Object?>> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final request = http.Request(method, _credentials.endpoint(path))
      ..headers['Authorization'] = 'Bearer ${_credentials.clientKey}'
      ..headers['Accept'] = 'application/json';
    if (body != null) {
      request
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);
    }
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _http.send(request).timeout(timeout),
      ).timeout(timeout);
    } on TimeoutException {
      throw const ApiException('The server did not answer in time');
    } on http.ClientException {
      throw const ApiException('Could not reach the server');
    }
    return _decode(response);
  }

  Map<String, Object?> _decode(http.Response response) {
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
