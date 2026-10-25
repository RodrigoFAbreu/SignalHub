import 'dart:convert';

import 'package:http/http.dart' as http;

import 'fakes.dart';

/// The producer side of the backend's client API, in memory, for the tests of
/// the producer screens: the producers the signed-in user owns with their
/// keys and allow-lists, the producers they see, and the people. Installed
/// into a [FakeBackend] as a handler.
class OwnProducersFake {
  OwnProducersFake(this.backend) {
    backend.handlers.add(_handle);
  }

  final FakeBackend backend;

  /// The ID of the signed-in user, as the fake registration says.
  static const meId = 'user-0';

  /// The producers the signed-in user owns, as the API answers them.
  final owned = <Map<String, Object?>>[];

  /// The producers somebody else owns that the signed-in user sees.
  final others = <Map<String, Object?>>[];

  /// The people on the server, as `GET /api/v1/client/users` lists them.
  final people = <Map<String, Object?>>[
    {'id': meId, 'name': 'Rodrigo'},
  ];

  /// Names taken by producers of other people, which nobody sees.
  final hiddenNames = <String>{};

  /// A status to answer the next request of that kind with, as
  /// `METHOD /path-pattern`; used once.
  final failures = <String, int>{};

  /// Requests made to the producer endpoints, as `METHOD path`.
  final calls = <String>[];

  /// Makes the next create answer as if its answer was lost on the way: the
  /// producer is made, the request fails with no answer.
  bool loseNextCreate = false;

  int _nextKey = 1;
  int _nextProducer = 1;

  static Map<String, Object?> key(
    String id, {
    String? prefix,
    String createdAt = '2026-09-27T09:00:00Z',
    String? lastUsedAt,
    String? revokedAt,
  }) => {
    'id': id,
    'prefix': prefix ?? 'shpk1_$id',
    'createdAt': createdAt,
    'lastUsedAt': lastUsedAt,
    'revokedAt': revokedAt,
  };

  /// Adds a producer the signed-in user owns.
  Map<String, Object?> own(
    String id,
    String name, {
    String visibility = 'PRIVATE',
    bool subscribed = true,
    List<Map<String, Object?>>? keys,
    List<Map<String, Object?>> allowed = const [],
    List<Map<String, Object?>> answerers = const [],
    String? disabledAt,
    bool disabledByOperator = false,
    String? lastEventAt,
  }) {
    final producer = <String, Object?>{
      'id': id,
      'name': name,
      'createdAt': '2026-09-27T09:00:00Z',
      'disabledAt': disabledAt,
      'disabledByOperator': disabledByOperator,
      'lastEventAt': lastEventAt,
      'visibility': visibility,
      'subscribed': subscribed,
      'allowedUsers': [...allowed],
      'answerers': [...answerers],
      'keys': keys ?? [key('EXAMPLE1')],
    };
    owned.add(producer);
    return producer;
  }

  /// Adds a producer somebody else owns that the signed-in user sees.
  Map<String, Object?> other(
    String id,
    String name,
    String ownerName, {
    String visibility = 'PUBLIC',
    bool subscribed = false,
    bool disabled = false,
    bool canAnswer = false,
  }) {
    final producer = <String, Object?>{
      'id': id,
      'name': name,
      'owner': {'id': 'owner-$ownerName', 'name': ownerName},
      'visibility': visibility,
      'disabled': disabled,
      'subscribed': subscribed,
      'canAnswer': canAnswer,
    };
    others.add(producer);
    return producer;
  }

  void addPerson(String id, String name) =>
      people.add({'id': id, 'name': name});

  Map<String, Object?>? _owned(String id) =>
      owned.where((p) => p['id'] == id).firstOrNull;

  Map<String, Object?>? _visible(String id) {
    for (final p in [...others, ...owned.map(_asVisible)]) {
      if (p['id'] == id) return p;
    }
    return null;
  }

  Map<String, Object?> _asVisible(Map<String, Object?> p) => {
    'id': p['id'],
    'name': p['name'],
    'owner': {'id': meId, 'name': backend.userName},
    'visibility': p['visibility'],
    'disabled': p['disabledAt'] != null,
    'subscribed': p['subscribed'],
    'canAnswer': true,
  };

  static http.Response _json(int status, Object body) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  static http.Response _problem(int status, String title) =>
      _json(status, {'title': title, 'status': status});

  Future<http.Response?> _handle(http.Request request, String path) async {
    if (!path.startsWith('/api/v1/client/')) return null;
    final rest = path.substring('/api/v1/client/'.length);
    final isOurs =
        rest.startsWith('producers') ||
        rest.startsWith('visible-producers') ||
        rest == 'users';
    if (!isOurs) return null;
    calls.add('${request.method} $path');
    final failure = failures.entries
        .where((f) => RegExp('^${f.key}\$').hasMatch('${request.method} $path'))
        .firstOrNull;
    if (failure != null) {
      failures.remove(failure.key);
      return _problem(failure.value, 'Failed');
    }
    final body = request.body.isEmpty
        ? const <String, Object?>{}
        : jsonDecode(request.body) as Map<String, Object?>;
    final route = '${request.method} /$rest';
    if (route == 'GET /users') return _json(200, {'items': people});
    if (route == 'GET /visible-producers') {
      return _json(200, {
        'items': [...others, ...owned.map(_asVisible)],
      });
    }
    final sub = RegExp(
      r'^(PUT|DELETE) /visible-producers/([^/]+)/subscription$',
    ).firstMatch(route);
    if (sub != null) return _subscription(sub.group(1)!, sub.group(2)!);
    if (route == 'GET /producers') return _json(200, {'items': owned});
    if (route == 'POST /producers') return _create(body);
    final match = RegExp(
      r'^(GET|PATCH|POST|PUT|DELETE) /producers/([^/]+)(/.*)?$',
    ).firstMatch(route);
    if (match == null) return null;
    final producer = _owned(match.group(2)!);
    if (producer == null) return _problem(404, 'Not found');
    return _change(request.method, producer, match.group(3) ?? '', body);
  }

  http.Response _subscription(String method, String id) {
    final visible = _visible(id);
    if (visible == null) return _problem(404, 'Not found');
    final subscribed = method == 'PUT';
    final ownedProducer = _owned(id);
    if (ownedProducer != null) ownedProducer['subscribed'] = subscribed;
    for (final p in others) {
      if (p['id'] == id) p['subscribed'] = subscribed;
    }
    return _json(200, _visible(id)!);
  }

  http.Response _create(Map<String, Object?> body) {
    final name = body['name'] as String;
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:/-]*$').hasMatch(name) ||
        name.length > 100) {
      return _problem(400, 'Bad Request');
    }
    final taken =
        owned.any((p) => p['name'] == name) ||
        others.any((p) => p['name'] == name) ||
        hiddenNames.contains(name);
    if (taken) return _problem(409, 'Conflict');
    final producer = own(
      'p-${_nextProducer++}',
      name,
      visibility: body['visibility'] as String? ?? 'PRIVATE',
      keys: [],
    );
    final issued = _issue(producer);
    if (loseNextCreate) {
      loseNextCreate = false;
      throw http.ClientException('lost', Uri.parse('https://signalhub.test'));
    }
    return _json(201, issued);
  }

  Map<String, Object?> _issue(Map<String, Object?> producer) {
    final id = 'NEW${_nextKey++}';
    (producer['keys']! as List).add(
      key(id, prefix: 'shpk1_$id', createdAt: '2026-10-10T09:00:00Z'),
    );
    return {
      'producer': producer,
      'keyId': id,
      'apiKey': 'shpk1_${id}_secret-key-shown-once-0000',
    };
  }

  http.Response _change(
    String method,
    Map<String, Object?> producer,
    String subpath,
    Map<String, Object?> body,
  ) {
    switch ('$method $subpath') {
      case 'GET ':
        return _json(200, producer);
      case 'PATCH ':
        final name = body['name'] as String?;
        if (name != null) {
          if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:/-]*$').hasMatch(name)) {
            return _problem(400, 'Bad Request');
          }
          final taken =
              (owned.any((p) => p['name'] == name && p != producer)) ||
              others.any((p) => p['name'] == name) ||
              hiddenNames.contains(name);
          if (taken) return _problem(409, 'Conflict');
          producer['name'] = name;
        }
        if (body['visibility'] case final String visibility) {
          producer['visibility'] = visibility;
        }
        return _json(200, producer);
      case 'POST /keys':
        return _json(201, _issue(producer));
      case 'POST /disable':
        producer['disabledAt'] = '2026-10-10T10:00:00Z';
        producer['disabledByOperator'] = false;
        return _json(200, producer);
      case 'POST /enable':
        if (producer['disabledByOperator'] == true) {
          return _problem(409, 'The operator disabled this producer');
        }
        producer['disabledAt'] = null;
        return _json(200, producer);
    }
    final revoke = RegExp(r'^POST /keys/([^/]+)/revoke$')
        .firstMatch('$method $subpath');
    if (revoke != null) {
      for (final k in producer['keys']! as List) {
        final keyJson = k as Map<String, Object?>;
        if (keyJson['id'] == revoke.group(1)) {
          keyJson['revokedAt'] = '2026-10-10T10:00:00Z';
        }
      }
      return _json(200, producer);
    }
    final allowed = RegExp(r'^(PUT|DELETE) /allowed-users/([^/]+)$')
        .firstMatch('$method $subpath');
    if (allowed != null) {
      final userId = allowed.group(2)!;
      final list = producer['allowedUsers']! as List;
      list.removeWhere((u) => (u as Map)['id'] == userId);
      if (allowed.group(1) == 'PUT') {
        final person = people.where((p) => p['id'] == userId).firstOrNull;
        if (person == null) return _problem(404, 'Not found');
        list.add({'id': userId, 'name': person['name']});
      }
      return _json(200, producer);
    }
    final answerers = RegExp(r'^(PUT|DELETE) /answerers/([^/]+)$')
        .firstMatch('$method $subpath');
    if (answerers != null) {
      final userId = answerers.group(2)!;
      final list = producer['answerers']! as List;
      list.removeWhere((u) => (u as Map)['id'] == userId);
      if (answerers.group(1) == 'PUT') {
        final person = people.where((p) => p['id'] == userId).firstOrNull;
        if (person == null) return _problem(404, 'Not found');
        list.add({'id': userId, 'name': person['name']});
      }
      return _json(200, producer);
    }
    return _problem(404, 'Not found');
  }
}
