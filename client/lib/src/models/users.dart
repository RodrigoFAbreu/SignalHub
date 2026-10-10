import 'json.dart';

/// What a user may do on the server (docs/architecture.md, "Roles"). Only the
/// host makes an [admin]; a role the app does not know counts as [basic], the
/// least a person may do.
enum UserRole {
  basic('BASIC', 'Basic'),
  mod('MOD', 'Mod'),
  admin('ADMIN', 'Admin');

  const UserRole(this.wireName, this.label);

  final String wireName;

  /// The word the app shows, as a tag or in a sentence.
  final String label;

  static UserRole parse(String value) =>
      values.firstWhere((r) => r.wireName == value, orElse: () => basic);

  /// Whether this role pairs, renames, revokes and deletes devices.
  bool get managesDevices => this != basic;

  bool get isAdmin => this == admin;
}

/// A user as a client's registration names its owner
/// (`user` of `GET /api/v1/client`).
class UserRef {
  const UserRef({required this.id, required this.name, required this.role});

  factory UserRef.fromJson(Map<String, Object?> json) => UserRef(
    id: json.string('id'),
    name: json.string('name'),
    role: UserRole.parse(json.string('role')),
  );

  final String id;
  final String name;
  final UserRole role;
}

/// A person on the server, as `GET /api/v1/client/users` lists them. Anyone
/// gets the name; only an admin's key also gets the role, the active devices
/// and whether they ever paired one.
class Person {
  const Person({
    required this.id,
    required this.name,
    this.role,
    this.activeDevices,
    this.hasPaired,
  });

  factory Person.fromJson(Map<String, Object?> json) => Person(
    id: json.string('id'),
    name: json.string('name'),
    role: json.optionalString('role') == null
        ? null
        : UserRole.parse(json.string('role')),
    activeDevices: json.optionalInteger('activeDevices'),
    hasPaired: json.optionalBoolean('hasPaired'),
  );

  final String id;
  final String name;

  /// `null` unless the list was read with an admin's key.
  final UserRole? role;
  final int? activeDevices;
  final bool? hasPaired;

  Person withRole(UserRole role) => Person(
    id: id,
    name: name,
    role: role,
    activeDevices: activeDevices,
    hasPaired: hasPaired,
  );
}

/// A producer a person owns, as an admin sees it on that person's page
/// (`GET /api/v1/client/users/{id}/producers`): never a key or an event.
class PersonProducer {
  const PersonProducer({
    required this.id,
    required this.name,
    required this.visibility,
    required this.disabled,
  });

  factory PersonProducer.fromJson(Map<String, Object?> json) => PersonProducer(
    id: json.string('id'),
    name: json.string('name'),
    visibility: ProducerVisibility.parse(json.string('visibility')),
    disabled: json.boolean('disabled'),
  );

  final String id;
  final String name;
  final ProducerVisibility visibility;
  final bool disabled;
}

/// Who may see a producer (docs/architecture.md, "Visibility and
/// subscriptions"). A value the app does not know counts as [private].
enum ProducerVisibility {
  public('PUBLIC', 'Public'),
  private('PRIVATE', 'Private');

  const ProducerVisibility(this.wireName, this.label);

  final String wireName;
  final String label;

  static ProducerVisibility parse(String value) =>
      values.firstWhere((v) => v.wireName == value, orElse: () => private);
}
