import 'package:flutter/foundation.dart';

import '../api/signalhub_api.dart';
import '../api_gateway.dart';
import '../models/producers.dart';
import '../models/users.dart';
import '../ui/event_style.dart';

/// How a subscription change ended.
enum SubscriptionOutcome {
  /// The server changed it.
  changed,

  /// The producer is gone for this user (`404`): its row is removed.
  gone,

  /// Nothing changed: the call failed, and the bell goes back.
  failed,

  /// Nothing was asked: a change to it was already running, or the app is
  /// back at setup.
  ignored,
}

/// One row of the Producers list: a producer this user sees, with what only
/// its owner is told when it is theirs. This is the one place the two lists
/// of the API meet: `visible-producers` (every producer, by name) and
/// `producers` (the ones this user owns, with keys and who may see them).
@immutable
class ProducerRow {
  const ProducerRow(this.producer, [this.own]);

  final VisibleProducer producer;

  /// What the owner is told of it; `null` for somebody else's producer.
  final OwnProducer? own;

  String get id => producer.id;
  String get name => producer.name;
  bool get isYours => own != null;
  bool get subscribed => producer.subscribed;

  /// Disabled by its owner or by the host. Somebody else's producer does not
  /// say which, so only the owner's own can be told apart.
  bool get disabled => own?.isDisabled ?? producer.disabled;

  bool get disabledByYou =>
      (own?.isDisabled ?? false) && !own!.disabledByOperator;
  bool get disabledByHost =>
      (own?.isDisabled ?? false) && own!.disabledByOperator;

  /// The row's second line, as DESIGN.md section 5 words it.
  /// [mutedOnDevice] says this device's push preferences mute the producer.
  String summary({bool mutedOnDevice = false}) {
    final own = this.own;
    if (own == null) {
      return [
        producer.owner.name,
        if (producer.disabled)
          'Disabled'
        else
          switch (producer.visibility) {
            ProducerVisibility.public => 'Public',
            ProducerVisibility.private => 'Private, shared with you',
          },
        if (mutedOnDevice && subscribed && !producer.disabled)
          'Muted on this device',
      ].join(' · ');
    }
    if (own.isDisabled) {
      return own.disabledByOperator
          ? 'Disabled by the host · ask the host'
          : 'Disabled by you · its keys do not work';
    }
    final isPrivate = producer.visibility == ProducerVisibility.private;
    final people = own.allowedUsers.length;
    final keys = own.workingKeys.length;
    final lastEvent = own.lastEventAt;
    return [
      isPrivate ? 'Private' : 'Public',
      if (isPrivate && people > 0)
        people == 1 ? '1 person' : '$people people'
      else
        keys == 1 ? '1 key' : '$keys keys',
      if (lastEvent == null)
        'no events yet'
      else
        'last event ${formatLastEvent(lastEvent)}',
      if (mutedOnDevice && subscribed) 'Muted on this device',
    ].join(' · ');
  }
}

/// A moment as the list says it: the time of day for today, otherwise the
/// date and time, local and to the minute.
String formatLastEvent(DateTime time, {DateTime? now}) {
  final t = time.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  if (t.year == today.year && t.month == today.month && t.day == today.day) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
  }
  return formatTimestamp(time);
}

/// The producers this user sees and subscribes to
/// (`/api/v1/client/visible-producers`), and the ones they own
/// (`/api/v1/client/producers`), which the Producers tab lists together.
class ProducersController extends ChangeNotifier {
  ProducersController(this.gateway);

  final ApiGateway gateway;

  /// Every producer this user sees, as last read.
  final Resource<List<VisibleProducer>> list = Resource();

  /// The producers this user owns, by ID, read with [list].
  Map<String, OwnProducer> _own = const {};

  /// Where a subscription change is running, by producer ID: the state it is
  /// moving to.
  final _changing = <String, bool>{};

  bool _disposed = false;

  /// Reads both lists again; the older ones stay if that fails.
  Future<void> load() async {
    if (list.loading) return;
    list.loading = true;
    notifyListeners();
    await list.load(() async {
      // Both are asked at once. `Future.wait` rethrows the first failure
      // itself, which a record's `wait` would wrap.
      final answers = await Future.wait<Object>([
        gateway.call((api) => api.listVisibleProducers()),
        gateway.call((api) => api.listOwnProducers()),
      ]);
      final visible = answers[0] as List<VisibleProducer>;
      final own = answers[1] as List<OwnProducer>;
      _own = {for (final p in own) p.id: p};
      return visible;
    });
    notifyListeners();
  }

  /// The producers this user is subscribed to, by name: the ones whose events
  /// the inbox holds, and the only ones it can be filtered by.
  List<VisibleProducer> get subscribed => [
    for (final p in list.value ?? const <VisibleProducer>[])
      if (p.subscribed) p,
  ];

  VisibleProducer? byId(String id) =>
      list.value?.where((p) => p.id == id).firstOrNull;

  /// Every producer as a row, in the list's order: the user's own, then the
  /// ones they are subscribed to, then the ones they can subscribe to, each
  /// A to Z; the disabled ones (by their owner or by the host) follow in the
  /// same order, at the bottom.
  List<ProducerRow> get rows {
    final visible = list.value ?? const <VisibleProducer>[];
    final seen = {for (final p in visible) p.id};
    final rows = [
      for (final p in visible) ProducerRow(p, _own[p.id]),
      // Owned, but not listed as visible: still the owner's to see.
      for (final own in _own.values)
        if (!seen.contains(own.id)) ProducerRow(_visibleFromOwn(own), own),
    ];
    int group(ProducerRow r) =>
        (r.disabled ? 3 : 0) + (r.isYours ? 0 : (r.subscribed ? 1 : 2));
    rows.sort((a, b) {
      final byGroup = group(a).compareTo(group(b));
      if (byGroup != 0) return byGroup;
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.id.compareTo(b.id);
    });
    return rows;
  }

  VisibleProducer _visibleFromOwn(OwnProducer own) => VisibleProducer(
    id: own.id,
    name: own.name,
    owner: UserName(id: gateway.userId ?? '', name: gateway.userName ?? ''),
    visibility: own.visibility,
    disabled: own.isDisabled,
    subscribed: own.subscribed,
  );

  /// Whether a subscription change to [id] is running.
  bool isChanging(String id) => _changing.containsKey(id);

  /// The state a running change to [id] is moving it to, or `null`.
  bool? changingTo(String id) => _changing[id];

  /// Subscribes to, or unsubscribes from, the producer [id]. The row shows
  /// the change as running until the server answers, and ignores another
  /// change to it meanwhile.
  Future<SubscriptionOutcome> setSubscribed(
    String id, {
    required bool subscribed,
  }) async {
    if (_changing.containsKey(id) ||
        byId(id) == null && !_own.containsKey(id)) {
      return SubscriptionOutcome.ignored;
    }
    _changing[id] = subscribed;
    notifyListeners();
    try {
      final changed = await gateway.call(
        (api) => subscribed ? api.subscribe(id) : api.unsubscribe(id),
      );
      _replace(changed);
      return SubscriptionOutcome.changed;
    } on SignedOutException {
      return SubscriptionOutcome.ignored;
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        _remove(id);
        return SubscriptionOutcome.gone;
      }
      return SubscriptionOutcome.failed;
    } finally {
      _changing.remove(id);
      notifyListeners();
    }
  }

  void _replace(VisibleProducer changed) {
    final visible = list.value;
    if (visible != null && visible.any((p) => p.id == changed.id)) {
      list.value = [for (final p in visible) p.id == changed.id ? changed : p];
    }
    if (_own[changed.id] case final own?) {
      _own = {..._own, changed.id: _withSubscribed(own, changed.subscribed)};
    }
  }

  static OwnProducer _withSubscribed(OwnProducer own, bool subscribed) =>
      OwnProducer(
        id: own.id,
        name: own.name,
        createdAt: own.createdAt,
        visibility: own.visibility,
        subscribed: subscribed,
        allowedUsers: own.allowedUsers,
        keys: own.keys,
        disabledAt: own.disabledAt,
        disabledByOperator: own.disabledByOperator,
        lastEventAt: own.lastEventAt,
      );

  void _remove(String id) {
    list.value = list.value?.where((p) => p.id != id).toList(growable: false);
    _own = {..._own}..remove(id);
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
