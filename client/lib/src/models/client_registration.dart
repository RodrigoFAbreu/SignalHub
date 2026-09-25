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

/// This installation's registration (`GET /api/v1/client`).
class ClientRegistration {
  const ClientRegistration({
    required this.id,
    required this.name,
    required this.createdAt,
    this.revokedAt,
    this.pushTarget,
  });

  factory ClientRegistration.fromJson(Map<String, Object?> json) {
    final pushTarget = json.optionalObject('pushTarget');
    return ClientRegistration(
      id: json.string('id'),
      name: json.string('name'),
      createdAt: json.timestamp('createdAt'),
      revokedAt: json.optionalTimestamp('revokedAt'),
      pushTarget: pushTarget == null
          ? null
          : PushTargetInfo.fromJson(pushTarget),
    );
  }

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime? revokedAt;
  final PushTargetInfo? pushTarget;
}
