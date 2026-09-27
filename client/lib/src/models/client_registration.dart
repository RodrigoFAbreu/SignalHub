import 'json.dart';

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

  /// Whether this installation is one of the owner's admin devices, which
  /// may manage the others.
  final bool admin;

  final DateTime? revokedAt;
  final PushTargetInfo? pushTarget;

  /// `null` from a server released before push preferences existed.
  final PushPreferences? pushPreferences;
}

/// One of the owner's clients, as an admin device lists them
/// (`GET /api/v1/client/devices`). The listing also has each client's push
/// target and results, which the app does not show.
class ManagedDevice {
  const ManagedDevice({
    required this.id,
    required this.name,
    required this.admin,
    required this.createdAt,
    this.revokedAt,
  });

  factory ManagedDevice.fromJson(Map<String, Object?> json) => ManagedDevice(
    id: json.string('id'),
    name: json.string('name'),
    admin: json.boolean('admin'),
    createdAt: json.timestamp('createdAt'),
    revokedAt: json.optionalTimestamp('revokedAt'),
  );

  final String id;
  final String name;
  final bool admin;
  final DateTime createdAt;
  final DateTime? revokedAt;

  bool get isRevoked => revokedAt != null;
}

/// A one-time pairing code this admin device created for a new device (the
/// backend's `Pairing`). The new device is never an admin.
class DevicePairing {
  const DevicePairing({
    required this.name,
    required this.code,
    required this.expiresAt,
    this.uri,
  });

  factory DevicePairing.fromJson(Map<String, Object?> json) => DevicePairing(
    name: json.string('name'),
    code: json.string('code'),
    expiresAt: json.timestamp('expiresAt'),
    uri: json.optionalString('uri'),
  );

  /// The name the new device gets.
  final String name;

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
