import 'package:flutter/foundation.dart';

import '../api/signalhub_api.dart';
import '../api_gateway.dart';
import '../models/client_registration.dart';
import '../models/users.dart';
import 'action_failure.dart';

/// What inviting someone made: the person and the code of their first
/// device, or why it did not work.
class InviteResult {
  const InviteResult.invited(UserRef this.user, DevicePairing this.pairing)
    : failure = null;

  const InviteResult.failed(ActionFailure this.failure)
    : user = null,
      pairing = null;

  final UserRef? user;
  final DevicePairing? pairing;
  final ActionFailure? failure;
}

/// The people on the server, for an admin (`/api/v1/client/users`): their
/// roles, active devices and producers, inviting someone and setting a role.
/// Making an admin and removing a person stay on the admin page.
class PeopleController extends ChangeNotifier {
  PeopleController(this.gateway);

  final ApiGateway gateway;

  /// Everyone who is not removed, as last read.
  final Resource<List<Person>> list = Resource();

  final _producers = <String, Resource<List<PersonProducer>>>{};
  final _removed = <String>{};

  /// The person whose role is being changed; `null` when none is.
  String? changingId;

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Reads the list again; the older one stays if that fails.
  Future<void> load() async {
    list.loading = true;
    notifyListeners();
    await list.load(() => gateway.call((api) => api.listPeople()));
    notifyListeners();
  }

  List<Person> get people => list.value ?? const [];

  Person? byId(String id) => people.where((p) => p.id == id).firstOrNull;

  /// Whether [id] is known to have been removed: a read of their page said
  /// so, or a fresh list no longer has them.
  bool wasRemoved(String id) =>
      _removed.contains(id) || (list.hasValue && byId(id) == null);

  /// The people with [role], in the order the server lists them.
  List<Person> withRole(UserRole role) => [
    for (final p in people)
      if ((p.role ?? UserRole.basic) == role) p,
  ];

  /// What a person's page lists of their producers: the producers they own,
  /// never a key or an event.
  Resource<List<PersonProducer>> producersOf(String id) =>
      _producers.putIfAbsent(id, Resource.new);

  /// Reads the producers of [id]. A person who is unknown (`404`) or removed
  /// (`409`) is [wasRemoved] from then on.
  Future<void> loadProducers(String id) async {
    final producers = producersOf(id);
    producers.loading = true;
    notifyListeners();
    await producers.load(
      () => gateway.call((api) => api.listPersonProducers(id)),
    );
    if (producers.error?.statusCode case 404 || 409) _removed.add(id);
    notifyListeners();
  }

  /// Invites a person called [name] and makes the code of their first
  /// device. The new person is in [list] once it is read again.
  Future<InviteResult> invite(
    String name, {
    required UserRole role,
    String? deviceName,
  }) async {
    final before = gateway.role;
    try {
      final made = await gateway.call(
        (api) => api.inviteUser(name, role: role, deviceName: deviceName),
      );
      return InviteResult.invited(made.user, made.pairing);
    } on SignedOutException {
      return const InviteResult.failed(ActionFailure.quiet());
    } on ApiException catch (e) {
      return InviteResult.failed(_inviteFailure(e, before));
    }
  }

  ActionFailure _inviteFailure(ApiException e, UserRole before) =>
      switch (e.statusCode) {
        409 => const ActionFailure(FailureKind.nameTaken, nameTakenMessage),
        403 => ActionFailure.refused(before, gateway.role),
        _ => ActionFailure.generic(e, 'make the invitation'),
      };

  static const nameTakenMessage =
      'Someone on this server already has that name. Use another.';

  /// Sets the role of [person], who is not an admin, to [role]. Returns why
  /// it did not work, or `null`.
  Future<ActionFailure?> setRole(Person person, UserRole role) async {
    changingId = person.id;
    notifyListeners();
    final before = gateway.role;
    try {
      final changed = await gateway.call(
        (api) => api.setUserRole(person.id, role),
      );
      list.value = [
        for (final p in people)
          if (p.id == person.id) p.withRole(changed.role) else p,
      ];
      return null;
    } on SignedOutException {
      return const ActionFailure.quiet();
    } on ApiException catch (e) {
      return await _roleFailure(person, e, before);
    } finally {
      changingId = null;
      notifyListeners();
    }
  }

  Future<ActionFailure?> _roleFailure(
    Person person,
    ApiException e,
    UserRole before,
  ) async {
    final status = e.statusCode;
    if (status == 403) return ActionFailure.refused(before, gateway.role);
    if (status != 404 && status != 409) {
      return ActionFailure.generic(e, 'change the role');
    }
    // Removed, or made an admin, meanwhile: the list says which.
    await load();
    final fresh = byId(person.id);
    if (fresh?.role == UserRole.admin) {
      return ActionFailure(
        FailureKind.adminTarget,
        '${person.name} is an admin. Admins are managed on the admin page.',
      );
    }
    if (fresh != null) return ActionFailure.generic(e, 'change the role');
    _removed.add(person.id);
    return ActionFailure(
      FailureKind.removed,
      "${possessive(person.name)} access was removed, so their role can't "
      'change.',
    );
  }
}
