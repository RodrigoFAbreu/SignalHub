import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'fakes.dart';

/// Today at [hour]:[minute], local time, as the API sends it (UTC): what the
/// list shows as `last event 01:19`.
String todayAt(int hour, int minute) {
  final now = DateTime.now();
  return DateTime(
    now.year,
    now.month,
    now.day,
    hour,
    minute,
  ).toUtc().toIso8601String();
}

/// The producers of an in-memory server for the Producers tests: what
/// `GET /api/v1/client/visible-producers` and `GET /api/v1/client/producers`
/// answer, and subscribing through `.../subscription`. Call [install] before
/// the app starts.
class FakeProducers {
  FakeProducers(this.backend) {
    install();
  }

  final FakeBackend backend;

  /// The producers this user sees, as the API lists them.
  final visible = <Map<String, Object?>>[];

  /// The producers this user owns, as the API lists them.
  final own = <Map<String, Object?>>[];

  /// Status the next subscription changes answer instead of working, by
  /// producer ID; `null` status: not reachable at all.
  final subscribeFailures = <String, int?>{};

  /// Status the lists answer instead of working; `0` for no answer at all.
  int? listFailure;

  /// While set, subscription changes and list reads are answered only once
  /// it completes: a change in flight, a list loading.
  Completer<void>? holdSubscriptions;
  Completer<void>? holdLists;

  /// How often each list was read.
  int visibleReads = 0;
  int ownReads = 0;

  /// The calls to `.../subscription`: `PUT id` or `DELETE id`.
  final subscriptionCalls = <String>[];

  void install() {
    backend.handlers.add(_handle);
  }

  /// A producer somebody else owns, as the visible list shows it.
  Map<String, Object?> visibleProducer(
    String id,
    String name, {
    String owner = 'Ana',
    bool private = false,
    bool disabled = false,
    bool subscribed = true,
  }) => {
    'id': id,
    'name': name,
    'owner': {'id': 'owner-$owner', 'name': owner},
    'visibility': private ? 'PRIVATE' : 'PUBLIC',
    'disabled': disabled,
    'subscribed': subscribed,
  };

  /// Adds somebody else's producer to the visible list.
  void addVisible(
    String id,
    String name, {
    String owner = 'Ana',
    bool private = false,
    bool disabled = false,
    bool subscribed = true,
  }) => visible.add(
    visibleProducer(
      id,
      name,
      owner: owner,
      private: private,
      disabled: disabled,
      subscribed: subscribed,
    ),
  );

  /// Adds a producer of this user's to both lists. [keys] counts the keys
  /// that work, [revokedKeys] the ones that do not; [people] names the allow
  /// list.
  void addOwn(
    String id,
    String name, {
    bool private = false,
    bool subscribed = true,
    int keys = 1,
    int revokedKeys = 0,
    List<String> people = const [],
    String? lastEventAt,
    bool paused = false,
    bool disabledByHost = false,
  }) {
    final disabledAt = paused || disabledByHost ? '2026-10-09T10:00:00Z' : null;
    own.add({
      'id': id,
      'name': name,
      'createdAt': '2026-09-01T08:00:00Z',
      'disabledAt': disabledAt,
      'disabledByOperator': disabledByHost,
      'lastEventAt': lastEventAt,
      'visibility': private ? 'PRIVATE' : 'PUBLIC',
      'subscribed': subscribed,
      'allowedUsers': [
        for (final p in people) {'id': 'person-$p', 'name': p},
      ],
      'keys': [
        for (var i = 0; i < keys + revokedKeys; i++)
          {
            'id': '$id-key-$i',
            'prefix': 'shpk1_EXAMPLE$i',
            'createdAt': '2026-09-01T08:00:00Z',
            'lastUsedAt': null,
            'revokedAt': i >= keys ? '2026-09-02T08:00:00Z' : null,
          },
      ],
    });
    visible.add({
      'id': id,
      'name': name,
      'owner': {'id': 'user-0', 'name': backend.userName},
      'visibility': private ? 'PRIVATE' : 'PUBLIC',
      'disabled': disabledAt != null,
      'subscribed': subscribed,
    });
  }

  Future<http.Response?> _handle(http.Request request, String path) async {
    final route = '${request.method} $path';
    if (route == 'GET /api/v1/client/visible-producers') {
      visibleReads++;
      await holdLists?.future;
      return _listed(visible);
    }
    if (route == 'GET /api/v1/client/producers') {
      ownReads++;
      await holdLists?.future;
      return _listed(own);
    }
    final id = RegExp(
      r'^/api/v1/client/visible-producers/([^/]+)/subscription$',
    ).firstMatch(path)?.group(1);
    if (id == null) return null;
    subscriptionCalls.add('${request.method} $id');
    await holdSubscriptions?.future;
    if (subscribeFailures.containsKey(id)) {
      final status = subscribeFailures[id];
      if (status == null) throw http.ClientException('offline', request.url);
      return _json(status, {'title': 'Failed', 'status': status});
    }
    final producer = visible.where((p) => p['id'] == id).firstOrNull;
    if (producer == null) return _json(404, {'title': 'Not found'});
    producer['subscribed'] = request.method == 'PUT';
    own
        .where((p) => p['id'] == id)
        .forEach((p) => p['subscribed'] = request.method == 'PUT');
    return _json(200, producer);
  }

  http.Response _listed(List<Map<String, Object?>> items) {
    if (listFailure case final status?) {
      if (status == 0) throw http.ClientException('offline', Uri());
      return _json(status, {'title': 'Failed', 'status': status});
    }
    return _json(200, {'items': items});
  }

  static http.Response _json(int status, Object body) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
}
