import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'fakes.dart';

/// A person on the fake server.
class FakeUser {
  FakeUser(this.id, this.name, this.role, {this.removed = false});

  final String id;
  final String name;
  String role;
  bool removed;
}

/// The users, devices and pairing codes of the client API
/// (`/api/v1/client/users`, `/devices`, `/pairings`) for the tests of the
/// people and devices screens, answering as docs/architecture.md describes
/// for each role. It is added to a [FakeBackend]'s `handlers` and answers
/// before the shared fake does. The caller is the fake's own device and user
/// (`user-0`, `backend.userName`), with the role the harness set.
class PeopleBackend {
  PeopleBackend(this.backend) {
    backend.handlers.add(_handle);
  }

  final FakeBackend backend;

  /// Everyone but the caller. Add with [addUser].
  final users = <FakeUser>[];

  /// Every device but the caller's own, as `ManagedClient` JSON.
  final devices = <Map<String, Object?>>[];

  /// The producers each user owns, by user ID.
  final producers = <String, List<Map<String, Object?>>>{};

  /// Users who have paired a device, by ID, beyond those with a device.
  final paired = <String>{};

  /// Pairing codes made from a device, in order: the request's `name` and
  /// the user it is for.
  final pairingsMade = <({String name, String userId})>[];
  final _used = <int, String>{};

  /// How the server answers a pairing for a user who was removed: `404` or
  /// `409`.
  int removedPairingStatus = 409;

  /// Fails only the per-person producers call with this status; the
  /// connection fails when it is `0`.
  int? producersFailWith;

  /// Whether the server has the user endpoints; one released before them
  /// answers `404`.
  bool userEndpoints = true;

  /// Fails every request of this client API with this status, once set; the
  /// connection fails when it is `0`.
  int? failWith;

  /// Which requests were made, as `METHOD /path`.
  final requests = <String>[];

  /// Whether the server refuses to revoke a mod's device as their last active
  /// one, whatever others they have.
  bool refuseLastActive = false;

  /// Whether pairings carry the server's `uri`; one with no public address
  /// configured leaves it out, and the app builds the link itself.
  bool pairingUris = true;

  /// When a pairing code made from a device expires.
  DateTime pairingExpiresAt = DateTime.utc(2026, 9, 27, 12, 10);

  /// The caller's own user ID.
  static const callerId = 'user-0';

  String get callerRole => backend.admin == true ? 'ADMIN' : backend.userRole;

  FakeUser addUser(
    String id,
    String name,
    String role, {
    bool removed = false,
  }) {
    final user = FakeUser(id, name, role, removed: removed);
    users.add(user);
    return user;
  }

  FakeUser? userById(String id) => users.where((u) => u.id == id).firstOrNull;

  /// A device of [userId]; an admin's devices are admin devices.
  Map<String, Object?> addDevice(
    String id,
    String name,
    String userId, {
    DateTime? lastActive,
    DateTime? revoked,
    bool browser = false,
  }) {
    final role = userId == callerId
        ? callerRole
        : userById(userId)?.role ?? 'BASIC';
    final device = <String, Object?>{
      'id': id,
      'name': name,
      'admin': role == 'ADMIN',
      'kind': browser ? 'BROWSER' : 'DEVICE',
      'user': {'id': userId, 'name': _nameOf(userId), 'role': role},
      'createdAt': '2026-09-26T08:00:00Z',
      'lastActiveAt': lastActive?.toUtc().toIso8601String(),
      // A browser's sign-in lasts a fixed 30 days.
      'expiresAt': browser ? '2026-11-09T12:00:00Z' : null,
      'revokedAt': revoked?.toUtc().toIso8601String(),
      'pushTarget': null,
      'pushPreferences': FakeBackend.defaultPushPreferences,
      'pushStatus': null,
    };
    devices.add(device);
    return device;
  }

  String _nameOf(String userId) =>
      userId == callerId ? backend.userName : userById(userId)!.name;

  /// The people and devices of the design's frames (3b, 3h): Rodrigo (the
  /// caller, an admin) and Sofia are admins, Ana is a mod, João, Marta and
  /// Rui are basic users and Rui has not paired yet.
  void seedDesignData(DateTime now) {
    addUser('user-1', 'Sofia', 'ADMIN');
    addUser('user-2', 'Ana', 'MOD');
    addUser('user-3', 'João', 'BASIC');
    addUser('user-4', 'Marta', 'BASIC');
    addUser('user-5', 'Rui', 'BASIC');
    addDevice('d-tablet', 'Rodrigo - Tablet', callerId, lastActive: now);
    addDevice('d-sofia', 'Sofia - Pixel', 'user-1', lastActive: now);
    addDevice('d-ana-pixel', 'Ana - Pixel', 'user-2', lastActive: now);
    addDevice(
      'd-ana-tablet',
      'Ana - Tablet',
      'user-2',
      lastActive: now.subtract(const Duration(days: 3)),
    );
    addDevice(
      'd-ana-old',
      'Ana - Old phone',
      'user-2',
      revoked: now.subtract(const Duration(days: 6)),
    );
    addDevice('d-joao', 'João - Galaxy', 'user-3');
    addDevice('d-marta', 'Marta - Phone', 'user-4', lastActive: now);
    // Rui has no device and has never paired one.
  }

  /// The devices of a mod or a basic user as the design draws them (3f, 3g):
  /// the caller's own, which are all they see, and other people's, which they
  /// never do.
  void seedOwnDevices(DateTime now) {
    addUser('user-1', 'Rodrigo', 'ADMIN');
    addUser('user-2', 'João', 'BASIC');
    addDevice('d-rodrigo', 'Rodrigo - Tablet', 'user-1', lastActive: now);
    addDevice('d-joao', 'João - Galaxy', 'user-2', lastActive: now);
    addDevice(
      'd-tablet',
      '${backend.userName} - Tablet',
      callerId,
      lastActive: now.subtract(const Duration(days: 3)),
    );
    addDevice(
      'd-old',
      '${backend.userName} - Old phone',
      callerId,
      revoked: now.subtract(const Duration(days: 6)),
    );
  }

  /// A device named [name] uses the code made [index]th from a device (the
  /// last by default): it is registered for the person it was made for.
  void usePairing(String name, {int? index}) {
    final at = index ?? pairingsMade.length - 1;
    final made = pairingsMade[at];
    _used[at] = name;
    addDevice('paired-$at', name, made.userId);
  }

  /// The pairing the app asks about is [index]th made.
  static String pairingId(int index) => 'pairing-$index';

  List<Map<String, Object?>> _allDevices() => [
    backend.clientJson(),
    ...devices,
  ];

  List<Map<String, Object?>> _visibleDevices() => callerRole == 'ADMIN'
      ? _allDevices()
      : [
          for (final d in _allDevices())
            if ((d['user']! as Map)['id'] == callerId) d,
        ];

  int _activeDevices(String userId) => [
    for (final d in _allDevices())
      if ((d['user']! as Map)['id'] == userId && d['revokedAt'] == null) d,
  ].length;

  bool _hasPaired(String userId) =>
      paired.contains(userId) ||
      _allDevices().any((d) => (d['user']! as Map)['id'] == userId);

  FutureOr<http.Response?> _handle(http.Request request, String path) {
    requests.add('${request.method} $path');
    if (!path.startsWith('/api/v1/client/users') &&
        !path.startsWith('/api/v1/client/devices') &&
        !path.startsWith('/api/v1/client/pairings')) {
      return null;
    }
    if (failWith case final status?) {
      if (status == 0) throw http.ClientException('offline', request.url);
      return _json(status, {'title': 'Failed', 'status': status});
    }
    final route = '${request.method} $path';
    if (path.startsWith('/api/v1/client/users')) {
      return userEndpoints ? _usersRoute(request, route) : _notFound();
    }
    if (path.startsWith('/api/v1/client/devices')) {
      return _devicesRoute(request, route);
    }
    return _pairingsRoute(request, route);
  }

  http.Response _usersRoute(http.Request request, String route) {
    final admin = callerRole == 'ADMIN';
    final person = RegExp(r'^/api/v1/client/users/([^/]+)(/producers)?$');
    switch (route) {
      case 'GET /api/v1/client/users':
        return _json(200, {'items': _people(admin: admin)});
      case 'POST /api/v1/client/users':
        return admin ? _invite(request) : _forbidden();
    }
    final match = person.firstMatch(route.split(' ').last);
    if (match == null) return _notFound();
    if (!admin) return _forbidden();
    final user = userById(match.group(1)!);
    if (match.group(2) != null && request.method == 'GET') {
      if (producersFailWith case final status?) {
        if (status == 0) throw http.ClientException('offline', request.url);
        return _json(status, {'title': 'Failed', 'status': status});
      }
      final id = match.group(1)!;
      if (id != callerId && (user == null || user.removed)) return _notFound();
      return _json(200, {'items': producers[id] ?? const []});
    }
    if (request.method == 'PATCH') {
      if (user == null) return _notFound();
      if (user.removed) {
        return _json(409, {'title': 'User is revoked', 'status': 409});
      }
      if (user.role == 'ADMIN') {
        return _json(409, {'title': 'User is an admin', 'status': 409});
      }
      final role =
          (jsonDecode(request.body) as Map<String, Object?>)['role']! as String;
      user.role = role;
      return _json(200, {'id': user.id, 'name': user.name, 'role': role});
    }
    return _notFound();
  }

  List<Map<String, Object?>> _people({required bool admin}) {
    final everyone = [
      (id: callerId, name: backend.userName, role: callerRole),
      for (final u in users)
        if (!u.removed) (id: u.id, name: u.name, role: u.role),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return [
      for (final u in everyone)
        {
          'id': u.id,
          'name': u.name,
          if (admin) ...{
            'role': u.role,
            'activeDevices': _activeDevices(u.id),
            'hasPaired': _hasPaired(u.id),
          },
        },
    ];
  }

  http.Response _invite(http.Request request) {
    final body = jsonDecode(request.body) as Map<String, Object?>;
    final name = (body['name']! as String).trim();
    final taken = [
      backend.userName,
      for (final u in users) u.name,
    ].any((n) => n.toLowerCase() == name.toLowerCase());
    if (taken) return _json(409, {'title': 'Name taken', 'status': 409});
    final user = addUser(
      'user-${users.length + 1}',
      name,
      (body['role'] as String?) ?? 'BASIC',
    );
    final pairing = _makePairing(
      (body['deviceName'] as String?) ?? 'First device',
      user.id,
    );
    return _json(201, {
      'user': {'id': user.id, 'name': user.name, 'role': user.role},
      'pairing': pairing,
    });
  }

  Map<String, Object?> _makePairing(String name, String userId) {
    final index = pairingsMade.length;
    pairingsMade.add((name: name, userId: userId));
    final code = 'shpc1_fromDevice${index}xxxxxxx';
    return {
      'id': pairingId(index),
      'name': name,
      'admin': userId == callerId ? callerRole == 'ADMIN' : false,
      'user': {
        'id': userId,
        'name': _nameOf(userId),
        'role': userId == callerId ? callerRole : userById(userId)!.role,
      },
      'code': code,
      'expiresAt': pairingExpiresAt.toIso8601String(),
      'uri': pairingUris
          ? Uri(
              scheme: 'signalhub',
              host: 'pair',
              queryParameters: {'server': serverUrl, 'code': code},
            ).toString()
          : null,
    };
  }

  http.Response _pairingsRoute(http.Request request, String route) {
    if (callerRole == 'BASIC') return _forbidden();
    if (route == 'POST /api/v1/client/pairings') {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      final userId = (body['userId'] as String?) ?? callerId;
      if (userId != callerId) {
        if (callerRole != 'ADMIN') return _forbidden();
        final user = userById(userId);
        if (user == null) return _notFound();
        if (user.removed) {
          return _json(removedPairingStatus, {
            'title': 'User is revoked',
            'status': removedPairingStatus,
          });
        }
      }
      return _json(201, _makePairing(body['name']! as String, userId));
    }
    final id = RegExp(r'^GET /api/v1/client/pairings/pairing-(\d+)$')
        .firstMatch(route)
        ?.group(1);
    final index = id == null ? null : int.parse(id);
    if (index == null || index >= pairingsMade.length) return _notFound();
    final used = _used[index];
    return _json(200, {
      'id': pairingId(index),
      'state': used == null ? 'PENDING' : 'REDEEMED',
      'expiresAt': pairingExpiresAt.toIso8601String(),
      'redeemedAt': used == null ? null : '2026-09-27T12:02:00Z',
      'client': used == null ? null : {'id': 'paired-$index', 'name': used},
    });
  }

  http.Response _devicesRoute(http.Request request, String route) {
    if (route == 'GET /api/v1/client/devices') {
      return _json(200, {'items': _visibleDevices()});
    }
    // Every change: the role is checked first, before the device is looked up.
    // Every role changes its own browsers; a basic user nothing else.
    final match = RegExp(r'^/api/v1/client/devices/([^/]+?)(/revoke)?$')
        .firstMatch(route.split(' ').last);
    final target = _allDevices()
        .where((d) => d['id'] == match?.group(1))
        .firstOrNull;
    final ownBrowser =
        target != null &&
        target['kind'] == 'BROWSER' &&
        (target['user']! as Map)['id'] == callerId;
    if (callerRole == 'BASIC' && !ownBrowser) return _forbidden();
    if (match == null) return _notFound();
    final device = _visibleDevices()
        .where((d) => d['id'] == match.group(1))
        .firstOrNull;
    if (device == null) return _notFound();
    final isAdminDevice = device['admin'] == true && !ownBrowser;
    final revoked = device['revokedAt'] != null;
    if (request.method == 'DELETE') {
      if (isAdminDevice) return _adminDevice();
      if (!revoked) {
        return _json(409, {'title': 'Client is not revoked', 'status': 409});
      }
      devices.remove(device);
      return http.Response('', 204);
    }
    if (isAdminDevice) return _adminDevice();
    if (match.group(2) != null && request.method == 'POST') {
      // The last active device of a mod stays; a browser is never one, and
      // does not count as another device.
      final isDevice = device['kind'] != 'BROWSER';
      if (!revoked && callerRole == 'MOD' && isDevice && refuseLastActive) {
        return _json(409, {
          'title': 'Cannot revoke the last active device of a user',
          'status': 409,
        });
      }
      if (!revoked && callerRole == 'MOD' && isDevice) {
        final others = _visibleDevices().where(
          (d) =>
              d['id'] != device['id'] &&
              d['revokedAt'] == null &&
              d['kind'] != 'BROWSER',
        );
        if (others.isEmpty) {
          return _json(409, {
            'title': 'Cannot revoke the last active device of a user',
            'status': 409,
          });
        }
      }
      device['revokedAt'] ??= '2026-10-10T09:00:00Z';
      return _json(200, device);
    }
    if (request.method == 'PATCH') {
      if (revoked) {
        return _json(409, {'title': 'Client is revoked', 'status': 409});
      }
      device['name'] =
          (jsonDecode(request.body) as Map<String, Object?>)['name'];
      return _json(200, device);
    }
    return _notFound();
  }

  static http.Response _adminDevice() =>
      _json(409, {'title': 'Client is an admin device', 'status': 409});

  static http.Response _forbidden() =>
      _json(403, {'title': 'Not allowed for your role', 'status': 403});

  static http.Response _notFound() =>
      _json(404, {'title': 'Not Found', 'status': 404});

  static http.Response _json(int status, Object body) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
}
