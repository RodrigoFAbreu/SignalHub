import 'json.dart';
import 'users.dart';

/// Where pushes for this client go, as the backend reports it. The token is
/// write-only in the API, so only the provider name comes back.
class PushTargetInfo {
  const PushTargetInfo({required this.provider, required this.updatedAt});

  factory PushTargetInfo.fromJson(Map<String, Object?> json) => PushTargetInfo(
    provider: json.string('provider'),
    updatedAt: json.timestamp('updatedAt'),
  );

  final String provider;
  final DateTime updatedAt;
}

/// Which events are pushed to this client (`pushPreferences`). An event is
/// pushed only when pushes are [enabled], its severity is at least
/// [minimumSeverity], and neither its category nor its producer is muted.
/// Events are stored and listed either way.
///
/// Severities and categories are kept as the server sends them, so values
/// added in a later backend release survive a change made by this app: the
/// backend replaces all preferences on every change.
class PushPreferences {
  const PushPreferences({
    this.enabled = true,
    this.minimumSeverity = 'LOW',
    this.mutedCategories = const [],
    this.mutedProducerIds = const [],
  });

  factory PushPreferences.fromJson(Map<String, Object?> json) =>
      PushPreferences(
        enabled: json.boolean('enabled'),
        minimumSeverity: json.string('minimumSeverity'),
        mutedCategories: json.strings('mutedCategories'),
        mutedProducerIds: json.strings('mutedProducerIds'),
      );

  final bool enabled;
  final String minimumSeverity;
  final List<String> mutedCategories;
  final List<String> mutedProducerIds;

  /// The body of `PUT /api/v1/client/push-preferences`.
  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'minimumSeverity': minimumSeverity,
    'mutedCategories': mutedCategories,
    'mutedProducerIds': mutedProducerIds,
  };

  PushPreferences copyWith({
    bool? enabled,
    String? minimumSeverity,
    List<String>? mutedCategories,
    List<String>? mutedProducerIds,
  }) => PushPreferences(
    enabled: enabled ?? this.enabled,
    minimumSeverity: minimumSeverity ?? this.minimumSeverity,
    mutedCategories: mutedCategories ?? this.mutedCategories,
    mutedProducerIds: mutedProducerIds ?? this.mutedProducerIds,
  );
}

/// This installation's registration (`GET /api/v1/client`).
class ClientRegistration {
  const ClientRegistration({
    required this.id,
    required this.name,
    required this.createdAt,
    this.admin = false,
    this.user,
    this.lastActiveAt,
    this.revokedAt,
    this.pushTarget,
    this.pushPreferences,
  });

  factory ClientRegistration.fromJson(Map<String, Object?> json) {
    final pushTarget = json.optionalObject('pushTarget');
    final pushPreferences = json.optionalObject('pushPreferences');
    return ClientRegistration(
      id: json.string('id'),
      name: json.string('name'),
      createdAt: json.timestamp('createdAt'),
      // Absent from a server released before admin devices existed.
      admin: json.optionalBoolean('admin') ?? false,
      user: json.optionalObjectAs('user', UserRef.fromJson),
      lastActiveAt: json.optionalTimestamp('lastActiveAt'),
      revokedAt: json.optionalTimestamp('revokedAt'),
      pushTarget: pushTarget == null
          ? null
          : PushTargetInfo.fromJson(pushTarget),
      pushPreferences: pushPreferences == null
          ? null
          : PushPreferences.fromJson(pushPreferences),
    );
  }

  final String id;
  final String name;
  final DateTime createdAt;

  /// Whether this installation is an admin device: exactly when its user is
  /// an admin.
  final bool admin;

  /// The user this installation belongs to, with their role; `null` from a
  /// server released before users.
  final UserRef? user;

  /// When this installation last made a request, to within a minute; `null`
  /// from a server that does not say.
  final DateTime? lastActiveAt;

  final DateTime? revokedAt;
  final PushTargetInfo? pushTarget;

  /// `null` from a server released before push preferences existed.
  final PushPreferences? pushPreferences;

  /// What this installation's user may do. A server released before users
  /// says only whether the device is an admin's.
  UserRole get role => user?.role ?? (admin ? UserRole.admin : UserRole.basic);
}

/// A client as a device lists it (`GET /api/v1/client/devices`): an
/// admin's key gets every client, anyone else's their own user's. The
/// listing also has each client's push target and results, which the app
/// does not show.
class ManagedDevice {
  const ManagedDevice({
    required this.id,
    required this.name,
    required this.admin,
    required this.createdAt,
    this.user,
    this.lastActiveAt,
    this.revokedAt,
    this.isBrowser = false,
  });

  factory ManagedDevice.fromJson(Map<String, Object?> json) => ManagedDevice(
    id: json.string('id'),
    name: json.string('name'),
    admin: json.boolean('admin'),
    createdAt: json.timestamp('createdAt'),
    user: json.optionalObjectAs('user', UserRef.fromJson),
    lastActiveAt: json.optionalTimestamp('lastActiveAt'),
    revokedAt: json.optionalTimestamp('revokedAt'),
  );

  final String id;
  final String name;

  /// Whether it is an admin device, which no device can change.
  final bool admin;
  final DateTime createdAt;

  /// Who it belongs to; `null` from a server released before users.
  final UserRef? user;

  /// When it last made a request, to within a minute; `null` until it has
  /// (and from a server that does not say).
  final DateTime? lastActiveAt;
  final DateTime? revokedAt;

  /// Whether it is a browser signed in to a web page. The server does not say
  /// so yet (R66 gives it a way to), so no device read from it is one; the
  /// row is drawn for when it does.
  final bool isBrowser;

  bool get isRevoked => revokedAt != null;

  ManagedDevice withName(String name) => ManagedDevice(
    id: id,
    name: name,
    admin: admin,
    createdAt: createdAt,
    user: user,
    lastActiveAt: lastActiveAt,
    revokedAt: revokedAt,
    isBrowser: isBrowser,
  );
}

/// A one-time pairing code this device created for a new device (the
/// backend's `Pairing`). The new device belongs to [user] and is an admin
/// device exactly when that user is an admin.
class DevicePairing {
  const DevicePairing({
    required this.name,
    required this.code,
    required this.expiresAt,
    this.id,
    this.uri,
    this.user,
  });

  factory DevicePairing.fromJson(Map<String, Object?> json) => DevicePairing(
    user: json.optionalObjectAs('user', UserRef.fromJson),
    // Absent from a server released before it could say whether a code was
    // used.
    id: json.optionalString('id'),
    name: json.string('name'),
    code: json.string('code'),
    expiresAt: json.timestamp('expiresAt'),
    uri: json.optionalString('uri'),
  );

  /// Asks whether the code was used ([PairingStatus]); not a secret. `null`
  /// from a server that cannot say.
  final String? id;

  /// The name the new device gets.
  final String name;

  /// The user the new device belongs to; `null` from a server that does not
  /// say.
  final UserRef? user;

  /// A one-time bearer credential. Never logged.
  final String code;

  /// When the code stops working, if unredeemed.
  final DateTime expiresAt;

  /// The pairing URI the server made from its public address; `null` when
  /// the operator configured none.
  final String? uri;

  @override
  String toString() => 'DevicePairing($name, expires $expiresAt)';
}

/// Whether a pairing code this admin device created was used (the backend's
/// `PairingStatus`). It never holds the code or a key.
class PairingStatus {
  const PairingStatus({required this.state, this.clientName});

  factory PairingStatus.fromJson(Map<String, Object?> json) {
    final client = json.optionalObject('client');
    return PairingStatus(
      state: json.string('state'),
      clientName: client?.string('name'),
    );
  }

  /// `PENDING`, `REDEEMED` or `EXPIRED`, as the server sends it; a state
  /// added later counts as pending.
  final String state;

  /// The name, as it is now, of the device that used the code; `null` until
  /// one has.
  final String? clientName;

  bool get isRedeemed => state == 'REDEEMED' && clientName != null;
}
