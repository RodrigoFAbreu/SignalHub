import 'package:flutter/foundation.dart';

import '../api/signalhub_api.dart';
import '../api_gateway.dart';
import '../models/producers.dart';
import '../models/users.dart';

/// Why a change to a producer did not happen, in the terms the screens say.
enum ProducerFailure {
  /// The key was revoked and the app is back at setup, which says why:
  /// nothing more to show.
  signedOut,

  /// The server does not know the producer for this user: it was made private
  /// or is not theirs.
  notFound,

  /// The name belongs to another producer (`409`).
  taken,

  /// The server does not accept the name (`400`).
  notAllowed,

  /// The host disabled the producer, so only the host can enable it (`409`).
  disabledByHost,

  /// The role does not allow it (`403`); the app has read the role again.
  forbidden,

  /// No answer from the server at all.
  offline,

  /// The server failed (`5xx`).
  server,

  /// Anything else the server refused.
  other,
}

/// What a call about producers answered: its [value], or why it did not
/// work.
class ProducerOutcome<T> {
  const ProducerOutcome.ok(T this.value) : failure = null;
  const ProducerOutcome.failed(ProducerFailure this.failure) : value = null;

  final T? value;
  final ProducerFailure? failure;

  bool get ok => failure == null;

  /// The sentence for the owner when the change did not work, in the words
  /// of the drawings, never the server's own title. [doing] completes
  /// _Couldn't …_, such as `rename homelab-monitor`. `null` when there is
  /// nothing to say: it worked, or the app returned to setup.
  String? message(String doing) => switch (failure) {
    null || ProducerFailure.signedOut => null,
    ProducerFailure.offline =>
      "Couldn't $doing. Check your connection and try again.",
    ProducerFailure.server => 'SignalHub had a problem. Try again in a moment.',
    ProducerFailure.forbidden =>
      "Your role doesn't allow this. It may have changed.",
    ProducerFailure.disabledByHost =>
      'Disabled by the host. Ask the host to enable it.',
    ProducerFailure.notFound ||
    ProducerFailure.taken ||
    ProducerFailure.notAllowed ||
    ProducerFailure.other => "Couldn't $doing. Try again.",
  };
}

/// The producers this user owns (`/api/v1/client/producers`): reading them,
/// creating one and everything that changes one, its keys and who may see
/// it. Every call answers a [ProducerOutcome] instead of throwing, so a
/// screen only decides what to say.
class OwnProducersController extends ChangeNotifier {
  OwnProducersController(this.gateway);

  final ApiGateway gateway;

  /// Every producer this user owns, as last read.
  final Resource<List<OwnProducer>> list = Resource();

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  /// Reads the list again; the older one stays if that fails.
  Future<void> load() async {
    list.loading = true;
    notifyListeners();
    await list.load(() => gateway.call((api) => api.listOwnProducers()));
    notifyListeners();
  }

  /// The producer with [id], if this user owns it and it was read.
  OwnProducer? byId(String id) =>
      list.value?.where((p) => p.id == id).firstOrNull;

  /// The producer this user owns called [name], if the list holds one.
  OwnProducer? byName(String name) =>
      list.value?.where((p) => p.name == name).firstOrNull;

  /// Reads one producer. `notFound` for one this user does not own.
  Future<ProducerOutcome<OwnProducer>> read(String id) =>
      _change(() => gateway.call((api) => api.getOwnProducer(id)));

  /// Registers a producer and issues its first key, which this answer holds
  /// and nothing else.
  Future<ProducerOutcome<IssuedProducerKey>> create(
    String name,
    ProducerVisibility visibility,
  ) => _issued(
    () =>
        gateway.call((api) => api.createProducer(name, visibility: visibility)),
  );

  Future<ProducerOutcome<OwnProducer>> rename(String id, String name) =>
      _change(() => gateway.call((api) => api.updateProducer(id, name: name)));

  Future<ProducerOutcome<OwnProducer>> setVisibility(
    String id,
    ProducerVisibility visibility,
  ) => _change(
    () => gateway.call((api) => api.updateProducer(id, visibility: visibility)),
  );

  /// Issues an additional key; its secret is in the answer only.
  Future<ProducerOutcome<IssuedProducerKey>> issueKey(String id) =>
      _issued(() => gateway.call((api) => api.issueProducerKey(id)));

  Future<ProducerOutcome<OwnProducer>> revokeKey(String id, String keyId) =>
      _change(() => gateway.call((api) => api.revokeProducerKey(id, keyId)));

  Future<ProducerOutcome<OwnProducer>> disable(String id) =>
      _change(() => gateway.call((api) => api.disableProducer(id)));

  /// `disabledByHost` if the host disabled it meanwhile: only the host
  /// enables it then.
  Future<ProducerOutcome<OwnProducer>> enable(String id) => _change(
    () => gateway.call((api) => api.enableProducer(id)),
    conflict: ProducerFailure.disabledByHost,
  );

  /// Subscribes this user to a producer they see, or ends it; idempotent.
  /// Their own producer's entry in [list] follows.
  Future<ProducerOutcome<VisibleProducer>> setSubscribed(
    String id, {
    required bool subscribed,
  }) async {
    final outcome = await _guard(
      () => gateway.call(
        (api) => subscribed ? api.subscribe(id) : api.unsubscribe(id),
      ),
    );
    final own = byId(id);
    if (outcome.ok && own != null) _store(own.withSubscribed(subscribed));
    return outcome;
  }

  /// Lets the people in [add] see a private producer and takes the people in
  /// [remove] off it, one by one, and stops at the first that fails. What
  /// worked before it stays in [list], so a screen shows what did happen.
  Future<ProducerOutcome<OwnProducer>> saveAllowList(
    String id, {
    required List<String> add,
    required List<String> remove,
  }) async {
    ProducerOutcome<OwnProducer>? last;
    for (final (userId, allowing) in [
      for (final u in add) (u, true),
      for (final u in remove) (u, false),
    ]) {
      last = await _change(
        () => gateway.call(
          (api) => allowing
              ? api.allowUser(id, userId)
              : api.disallowUser(id, userId),
        ),
      );
      if (!last.ok) return last;
    }
    return last ?? read(id);
  }

  /// Names the people in [add] to answer the producer's questions, one by one,
  /// stopping at the first that fails. What worked stays in [list].
  Future<ProducerOutcome<OwnProducer>> addAnswerers(
    String id,
    List<String> add,
  ) async {
    ProducerOutcome<OwnProducer>? last;
    for (final userId in add) {
      last = await _change(
        () => gateway.call((api) => api.addAnswerer(id, userId)),
        conflict: ProducerFailure.notAllowed,
      );
      if (!last.ok) return last;
    }
    return last ?? read(id);
  }

  /// Takes one person off the producer's answerers. Their earlier answers stay
  /// as they are.
  Future<ProducerOutcome<OwnProducer>> removeAnswerer(
    String id,
    String userId,
  ) => _change(() => gateway.call((api) => api.removeAnswerer(id, userId)));

  /// The people on the server a private producer can be shared with, by name
  /// and A to Z. This user is left out: a producer is always theirs to see.
  Future<ProducerOutcome<List<Person>>> readPeople() async {
    final outcome = await _guard(() => gateway.call((api) => api.listPeople()));
    final people = outcome.value;
    if (people == null) return ProducerOutcome.failed(outcome.failure!);
    final me = gateway.userId;
    return ProducerOutcome.ok(
      [
        for (final p in people)
          if (p.id != me) p,
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
    );
  }

  Future<ProducerOutcome<OwnProducer>> _change(
    Future<OwnProducer> Function() call, {
    ProducerFailure conflict = ProducerFailure.taken,
  }) async {
    final outcome = await _guard(call, conflict: conflict);
    if (outcome.value case final producer?) _store(producer);
    return outcome;
  }

  Future<ProducerOutcome<IssuedProducerKey>> _issued(
    Future<IssuedProducerKey> Function() call,
  ) async {
    final outcome = await _guard(call);
    if (outcome.value case final issued?) _store(issued.producer);
    return outcome;
  }

  Future<ProducerOutcome<T>> _guard<T>(
    Future<T> Function() call, {
    ProducerFailure conflict = ProducerFailure.taken,
  }) async {
    try {
      return ProducerOutcome.ok(await call());
    } on SignedOutException {
      return const ProducerOutcome.failed(ProducerFailure.signedOut);
    } on ApiException catch (e) {
      return ProducerOutcome.failed(_failureOf(e, conflict));
    }
  }

  /// A `409` means a taken name for the calls that name one and a producer
  /// the host disabled for enabling it, so the call says which.
  ProducerFailure _failureOf(ApiException e, ProducerFailure conflict) =>
      switch (e.statusCode) {
        null => ProducerFailure.offline,
        400 => ProducerFailure.notAllowed,
        403 => ProducerFailure.forbidden,
        404 => ProducerFailure.notFound,
        409 => conflict,
        >= 500 => ProducerFailure.server,
        _ => ProducerFailure.other,
      };

  /// Keeps [producer] in [list], where the list was read; a producer made
  /// here joins it.
  void _store(OwnProducer producer) {
    final current = list.value;
    if (current != null) {
      final known = current.any((p) => p.id == producer.id);
      list.value = [
        for (final p in current)
          if (p.id == producer.id) producer else p,
        if (!known) producer,
      ];
    }
    notifyListeners();
  }
}
