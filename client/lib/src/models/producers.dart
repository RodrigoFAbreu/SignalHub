import 'json.dart';
import 'users.dart';

/// A person named in a producer: its owner, or someone on its allow-list.
class UserName {
  const UserName({required this.id, required this.name});

  factory UserName.fromJson(Map<String, Object?> json) =>
      UserName(id: json.string('id'), name: json.string('name'));

  final String id;
  final String name;
}

/// A producer the caller's user may see
/// (`GET /api/v1/client/visible-producers`): never a key, an allow-list or
/// when it last published.
class VisibleProducer {
  const VisibleProducer({
    required this.id,
    required this.name,
    required this.owner,
    required this.visibility,
    required this.disabled,
    required this.subscribed,
  });

  factory VisibleProducer.fromJson(Map<String, Object?> json) =>
      VisibleProducer(
        id: json.string('id'),
        name: json.string('name'),
        owner: UserName.fromJson(json.object('owner')),
        visibility: ProducerVisibility.parse(json.string('visibility')),
        disabled: json.boolean('disabled'),
        subscribed: json.boolean('subscribed'),
      );

  final String id;
  final String name;
  final UserName owner;
  final ProducerVisibility visibility;

  /// Disabled by its owner or by the host: the app cannot tell which for a
  /// producer that is not the caller's own.
  final bool disabled;
  final bool subscribed;

  VisibleProducer withSubscribed(bool subscribed) => VisibleProducer(
    id: id,
    name: name,
    owner: owner,
    visibility: visibility,
    disabled: disabled,
    subscribed: subscribed,
  );
}

/// One key of a producer the caller owns, by prefix: never the key itself.
class ProducerKeyInfo {
  const ProducerKeyInfo({
    required this.id,
    required this.prefix,
    required this.createdAt,
    this.lastUsedAt,
    this.revokedAt,
  });

  factory ProducerKeyInfo.fromJson(Map<String, Object?> json) =>
      ProducerKeyInfo(
        id: json.string('id'),
        prefix: json.string('prefix'),
        createdAt: json.timestamp('createdAt'),
        lastUsedAt: json.optionalTimestamp('lastUsedAt'),
        revokedAt: json.optionalTimestamp('revokedAt'),
      );

  final String id;

  /// `shpk1_` and the key's ID, which is not secret.
  final String prefix;
  final DateTime createdAt;

  /// `null` until the key publishes, and from a server that does not say.
  final DateTime? lastUsedAt;
  final DateTime? revokedAt;

  bool get isRevoked => revokedAt != null;
}

/// A producer the caller owns (`OwnProducer`): its state, keys and
/// allow-list.
class OwnProducer {
  const OwnProducer({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.visibility,
    required this.subscribed,
    required this.allowedUsers,
    required this.keys,
    this.disabledAt,
    this.disabledByOperator = false,
    this.lastEventAt,
  });

  factory OwnProducer.fromJson(Map<String, Object?> json) => OwnProducer(
    id: json.string('id'),
    name: json.string('name'),
    createdAt: json.timestamp('createdAt'),
    disabledAt: json.optionalTimestamp('disabledAt'),
    disabledByOperator: json.optionalBoolean('disabledByOperator') ?? false,
    lastEventAt: json.optionalTimestamp('lastEventAt'),
    visibility: ProducerVisibility.parse(json.string('visibility')),
    subscribed: json.boolean('subscribed'),
    allowedUsers: json
        .list('allowedUsers')
        .map((u) => UserName.fromJson(asObject(u, 'allowedUsers[]')))
        .toList(growable: false),
    keys: json
        .list('keys')
        .map((k) => ProducerKeyInfo.fromJson(asObject(k, 'keys[]')))
        .toList(growable: false),
  );

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime? disabledAt;

  /// Whether the host disabled it: then only the host enables it.
  final bool disabledByOperator;
  final DateTime? lastEventAt;
  final ProducerVisibility visibility;
  final bool subscribed;
  final List<UserName> allowedUsers;
  final List<ProducerKeyInfo> keys;

  bool get isDisabled => disabledAt != null;

  /// Keys that still work.
  List<ProducerKeyInfo> get workingKeys =>
      keys.where((k) => !k.isRevoked).toList(growable: false);
}

/// What creating a producer or issuing a key answers (`IssuedOwnApiKey`):
/// the producer and its new key, **shown only here**. Never logged.
class IssuedProducerKey {
  const IssuedProducerKey({
    required this.producer,
    required this.keyId,
    required this.apiKey,
  });

  factory IssuedProducerKey.fromJson(Map<String, Object?> json) =>
      IssuedProducerKey(
        producer: OwnProducer.fromJson(json.object('producer')),
        keyId: json.string('keyId'),
        apiKey: json.string('apiKey'),
      );

  final OwnProducer producer;
  final String keyId;
  final String apiKey;

  @override
  String toString() => 'IssuedProducerKey(${producer.name}, $keyId)';
}

/// The server's release, for _About this server_
/// (`GET /api/v1/client/server`).
class ServerInfo {
  const ServerInfo({required this.version, this.commit});

  factory ServerInfo.fromJson(Map<String, Object?> json) => ServerInfo(
    version: json.string('version'),
    commit: json.optionalString('commit'),
  );

  /// `development` for a build no release made.
  final String version;
  final String? commit;
}
