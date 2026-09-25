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
  final DateTime? revokedAt;
  final PushTargetInfo? pushTarget;

  /// `null` from a server released before push preferences existed.
  final PushPreferences? pushPreferences;
}
