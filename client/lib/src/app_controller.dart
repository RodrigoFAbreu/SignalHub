import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api/signalhub_api.dart';
import 'build_identity.dart';
import 'connection/pairing_uri.dart';
import 'connection/server_credentials.dart';
import 'models/client_registration.dart';
import 'models/event.dart';
import 'models/inbox_filter.dart';
import 'models/push_config.dart';
import 'push/push_registration.dart';
import 'push/push_service.dart';

enum ConnectionPhase {
  /// Reading saved credentials.
  starting,

  /// No server configured: the setup screen.
  disconnected,

  /// Credentials saved and accepted by the server at least once.
  connected,
}

typedef ApiFactory = SignalHubApi Function(ServerCredentials credentials);

/// Redeems a pairing code at a server ([SignalHubApi.redeemPairing]).
typedef PairingRedeemer = Future<PairedClient> Function(
  String serverUrl,
  String code,
);

/// Starts push with options a server served, or returns `null` when they do
/// not work with this app.
typedef ServedPushStarter = Future<PushService?> Function(PushConfig served);

/// The app's state: the server connection, this installation's registration
/// and push status, and the inbox. The UI only renders it.
class AppController extends ChangeNotifier {
  /// [push] is the push service the build set up with its own options.
  /// Without one, [startServedPush] sets push up with the options the server
  /// serves; the build's own options take precedence.
  AppController({
    required this._store,
    required this._apiFactory,
    required this._redeemPairing,
    PushService? push,
    ServedPushStarter? startServedPush,
    this.build = BuildIdentity.compiled,
  }) : _push = push,
       _startServedPush = push == null ? startServedPush : null {
    _notices = push?.notices.listen(_onNotice);
  }

  /// Events per inbox page.
  static const pageSize = 30;

  final CredentialsStore _store;
  final ApiFactory _apiFactory;
  final PairingRedeemer _redeemPairing;
  PushService? _push;
  final ServedPushStarter? _startServedPush;
  StreamSubscription<PushNotice>? _notices;

  /// The served options push was set up with; `null` until then.
  PushConfig? _servedPushConfig;
  Future<PushService?>? _startingServedPush;

  /// Which SignalHub build this app is.
  final BuildIdentity build;

  SignalHubApi? _api;
  PushRegistration? _pushRegistration;

  ConnectionPhase phase = ConnectionPhase.starting;
  ServerCredentials? credentials;
  ClientRegistration? registration;
  late PushStatus pushStatus = _initialPushStatus;

  PushStatus get _initialPushStatus => _push == null && _startServedPush == null
      ? PushStatus.unavailable
      : PushStatus.pending;

  /// Why the last refresh or setup failed, for the owner; `null` if it
  /// worked.
  String? error;

  /// Whether the last refresh got no answer from the server at all. Nothing
  /// else can reach it then either, so push registration is not tried and
  /// [error] is the one thing to tell the owner.
  bool serverUnreachable = false;

  /// The inbox: the events read so far that match [filter], newest first.
  List<Event> events = const [];

  /// Which events the inbox shows. Kept only while the app runs: it starts
  /// with every event, so an inbox left filtered never hides new events
  /// after a restart.
  InboxFilter filter = InboxFilter.none;

  /// How many events are unread on the server, including events not read
  /// into [events] yet; `null` until known.
  int? unreadCount;

  /// Whether the first page of the inbox has been read since connecting.
  bool inboxLoaded = false;

  /// Whether an older page is being read.
  bool loadingMore = false;

  /// Why reading an older page failed; `null` if it worked.
  String? loadMoreError;

  String? _nextCursor;

  /// Counts inbox reloads, so an older page requested before a reload is not
  /// appended after it.
  int _inboxGeneration = 0;

  /// The event of a notification the owner tapped, until the inbox opens it.
  String? _eventToOpen;

  /// Whether a change to the push preferences is being saved.
  bool savingPushPreferences = false;

  /// Whether the server has events older than [events].
  bool get hasMore => _nextCursor != null;

  /// The producers of the events the inbox has read since connecting, by id:
  /// kept when a filter hides their events, so they can still be chosen.
  final _producers = <String, EventProducer>{};

  /// The producers of the events the inbox has read since connecting, by
  /// name. Client keys cannot list producers, so these are the ones the owner
  /// can filter by or mute by name.
  List<EventProducer> get inboxProducers =>
      _producers.values.toList()..sort((a, b) => a.name.compareTo(b.name));

  /// Whether _Mark all as read_ can be offered: it marks every unread event
  /// up to the newest one shown, so not while the filter hides some of them.
  bool get canMarkAllRead => !filter.narrowsEvents;

  /// Loads saved credentials and, if there are any, connects.
  Future<void> start() async {
    final saved = await _store.load();
    if (saved == null) {
      _eventToOpen = null;
      _setPhase(ConnectionPhase.disconnected);
      return;
    }
    _open(saved);
    _setPhase(ConnectionPhase.connected);
    await refresh();
  }

  /// Connects to a server with a client key typed by the owner. Saves them
  /// only once the server accepts the key. Returns an error message, or
  /// `null` on success.
  Future<String?> connect(String serverUrl, String clientKey) async {
    final ServerCredentials parsed;
    try {
      parsed = ServerCredentials.parse(serverUrl, clientKey);
    } on FormatException catch (e) {
      return e.message;
    }
    final api = _apiFactory(parsed);
    final ClientRegistration accepted;
    try {
      accepted = await api.getClient();
    } on ApiException catch (e) {
      return e.message;
    }
    await _connected(parsed, accepted);
    return null;
  }

  /// Registers this installation with a pairing code the owner scanned or
  /// pasted ([PairingUri]), and connects with the client key it returns.
  /// Returns an error message, or `null` on success.
  Future<String?> pair(String pairingUri) async {
    final PairingUri parsed;
    try {
      parsed = PairingUri.parse(pairingUri);
    } on FormatException catch (e) {
      return e.message;
    }
    final PairedClient paired;
    final ServerCredentials credentials;
    try {
      paired = await _redeemPairing(parsed.serverUrl, parsed.code);
      credentials = ServerCredentials.parse(parsed.serverUrl, paired.clientKey);
    } on ApiException catch (e) {
      // Name the server the code points to: it may not be reachable from
      // this device.
      return e.statusCode == null
          ? '${e.message} (${parsed.serverUrl})'
          : e.message;
    } on FormatException {
      return 'The server sent an unexpected answer';
    }
    await _connected(credentials, paired.registration);
    return null;
  }

  /// Saves credentials the server has accepted and shows the inbox.
  Future<void> _connected(
    ServerCredentials accepted,
    ClientRegistration client,
  ) async {
    registration = client;
    await _store.save(accepted);
    _open(accepted);
    error = null;
    _setPhase(ConnectionPhase.connected);
    await refresh(includeClient: false);
  }

  /// Re-reads the registration and the newest page of the inbox, and
  /// registers the push token again (pull to refresh).
  Future<void> refresh({bool includeClient = true}) async {
    if (await _reload(includeClient: includeClient) && !serverUnreachable) {
      await _registerPush();
    }
  }

  /// Returns whether the server still accepts the key.
  Future<bool> _reload({bool includeClient = true}) async {
    final api = _api;
    if (api == null) return false;
    try {
      if (includeClient) registration = await api.getClient();
      final generation = ++_inboxGeneration;
      final filter = this.filter;
      final page = await api.listEvents(limit: pageSize, filter: filter);
      final unread = await api.unreadCount();
      if (generation == _inboxGeneration) {
        _showFirstPage(page, filter);
        unreadCount = unread;
      }
      error = null;
      serverUnreachable = false;
    } on UnauthorizedException {
      await _forgetRevokedKey();
      return false;
    } on ApiException catch (e) {
      error = e.message;
      serverUnreachable = e.statusCode == null;
    }
    notifyListeners();
    return true;
  }

  void _showFirstPage(EventPage page, InboxFilter filter) {
    events = _shown(page, filter);
    _nextCursor = page.nextCursor;
    inboxLoaded = true;
    loadMoreError = null;
  }

  /// Appends the next older page of the inbox, if there is one.
  Future<void> loadMore() async {
    final api = _api;
    final cursor = _nextCursor;
    if (api == null || cursor == null || loadingMore) return;
    final generation = _inboxGeneration;
    final filter = this.filter;
    loadingMore = true;
    loadMoreError = null;
    notifyListeners();
    try {
      final page = await api.listEvents(
        limit: pageSize,
        cursor: cursor,
        filter: filter,
      );
      if (generation == _inboxGeneration) {
        events = [...events, ..._shown(page, filter)];
        _nextCursor = page.nextCursor;
      }
    } on UnauthorizedException {
      await _forgetRevokedKey();
      return;
    } on ApiException catch (e) {
      if (generation == _inboxGeneration) loadMoreError = e.message;
    }
    loadingMore = false;
    notifyListeners();
  }

  /// The events of [page] the inbox shows, noting their producers. Read
  /// events are dropped from the unread-only view because a server released
  /// before the `read` filter ignores it; events read while shown stay until
  /// the inbox is read again.
  List<Event> _shown(EventPage page, InboxFilter filter) {
    for (final event in page.items) {
      _producers[event.producer.id] = event.producer;
    }
    return page.items.where(filter.admits).toList(growable: false);
  }

  /// Shows only the events [next] admits, from the newest page. Pages read
  /// with the previous filter are dropped, as is any still arriving.
  Future<void> setFilter(InboxFilter next) async {
    if (next == filter || _api == null) return;
    filter = next;
    events = const [];
    _nextCursor = null;
    inboxLoaded = false;
    loadMoreError = null;
    notifyListeners();
    await _reload(includeClient: false);
  }

  /// Shows every event again.
  Future<void> clearFilter() => setFilter(InboxFilter.none);

  /// The event with [id]: from the inbox if it is there, otherwise from the
  /// server. Throws an [ApiException] if it cannot be read.
  Future<Event> event(String id) async {
    if (_eventWithId(id) case final event?) return event;
    final api = _api;
    if (api == null) throw const ApiException('Not connected to a server');
    return api.getEvent(id);
  }

  /// Marks the event with [id] read, for every client of the owner, when the
  /// owner opens it. Returns the event as the server returned it, or an
  /// error message if marking failed. Failing is harmless: the event stays
  /// unread and is marked again the next time it is opened.
  Future<({Event? event, String? error})> markRead(String id) async {
    if (_eventWithId(id) case final event? when event.isRead) {
      return (event: event, error: null);
    }
    return setRead(id, read: true);
  }

  /// Marks the event with [id] read when [read], unread otherwise. Returns
  /// the event as the server returned it, or an error message; neither if
  /// the key was revoked and the app returned to setup.
  Future<({Event? event, String? error})> setRead(
    String id, {
    required bool read,
  }) async {
    Event? changed;
    final error = await _changeReadState(() async {
      final api = _api!;
      final event = await (read ? api.markRead(id) : api.markUnread(id));
      _replaceEvent(event);
      changed = event;
      await _readUnreadCount();
    });
    return (event: error == null ? changed : null, error: error);
  }

  /// Marks read every event up to the newest one shown. Events that arrived
  /// since stay unread, so nothing the owner has not seen is marked. Does
  /// nothing unless [canMarkAllRead]. Returns an error message, or `null` on
  /// success.
  Future<String?> markAllRead() async {
    final newest = events.firstOrNull;
    if (newest == null || !canMarkAllRead) return null;
    return _changeReadState(() async {
      await _api!.markReadThrough(newest.id);
      // The server answers only a count. Every event shown is at or before
      // the newest one, so all of them are read now; the time is the app's
      // estimate, and a reload shows the server's.
      final now = DateTime.now().toUtc();
      events = [for (final e in events) e.isRead ? e : e.withReadAt(now)];
      await _readUnreadCount();
    });
  }

  /// Runs a read-state change against the server. Returns an error message,
  /// or `null` on success.
  Future<String?> _changeReadState(Future<void> Function() change) async {
    if (_api == null) return 'Not connected to a server';
    try {
      await change();
    } on UnauthorizedException {
      await _forgetRevokedKey();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } finally {
      notifyListeners();
    }
    return null;
  }

  /// After a change the server has made: if the count cannot be read, the
  /// change still stands and the next reload corrects the count.
  Future<void> _readUnreadCount() async {
    final api = _api;
    if (api == null) return;
    try {
      unreadCount = await api.unreadCount();
    } on UnauthorizedException {
      rethrow;
    } on ApiException catch (e) {
      debugPrint('Unread count not updated: ${e.message}');
    }
  }

  Event? _eventWithId(String id) => events.where((e) => e.id == id).firstOrNull;

  void _replaceEvent(Event updated) {
    events = [for (final e in events) e.id == updated.id ? updated : e];
  }

  /// Replaces which events are pushed to this installation. Returns an error
  /// message, or `null` on success; on failure the registration keeps the
  /// server's last answer.
  Future<String?> setPushPreferences(PushPreferences preferences) async {
    final api = _api;
    if (api == null) return 'Not connected to a server';
    savingPushPreferences = true;
    notifyListeners();
    try {
      registration = await api.setPushPreferences(preferences);
    } on UnauthorizedException {
      await _forgetRevokedKey();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } finally {
      savingPushPreferences = false;
      notifyListeners();
    }
    return null;
  }

  /// The event of a notification the owner tapped, once: the inbox opens it.
  String? takeEventToOpen() {
    final id = _eventToOpen;
    _eventToOpen = null;
    return id;
  }

  /// Stops pushes to this installation and forgets the server.
  Future<void> disconnect() async {
    await _pushRegistration?.unregister();
    await _forget(null);
  }

  void _open(ServerCredentials saved) {
    credentials = saved;
    _api = _apiFactory(saved);
    final push = _push;
    if (push != null) _pushRegistration = PushRegistration(push, _api!);
  }

  Future<void> _registerPush() async {
    if (_startServedPush != null && !await _servedPushReady()) {
      notifyListeners();
      return;
    }
    final registration = _pushRegistration;
    if (registration == null) return;
    pushStatus = await registration.register();
    notifyListeners();
  }

  /// For a build without its own push options: sets push up with the options
  /// the server serves, the first time, and afterwards checks that the server
  /// still serves those, since the provider starts only once per process.
  /// Returns whether push can register; if not, [pushStatus] says why.
  Future<bool> _servedPushReady() async {
    final api = _api;
    if (api == null) return false;
    final PushConfig? served;
    try {
      served = await api.getPushConfig();
    } on UnauthorizedException {
      await _forgetRevokedKey();
      return false;
    } on ApiException catch (e) {
      debugPrint('Push options not read: ${e.message}');
      pushStatus = PushStatus.failed;
      return false;
    }
    if (served == null) {
      pushStatus = PushStatus.notConfigured;
      return false;
    }
    if (_servedPushConfig case final startedWith?) {
      if (startedWith.sameAs(served)) return true;
      pushStatus = PushStatus.restartRequired;
      return false;
    }
    // Concurrent refreshes share one start: the provider starts only once.
    final push = await (_startingServedPush ??= _startServedPush!(served));
    if (push == null) {
      _startingServedPush = null;
      pushStatus = PushStatus.unsupported;
      return false;
    }
    if (_servedPushConfig == null) {
      _servedPushConfig = served;
      _push = push;
      _notices = push.notices.listen(_onNotice);
      if (_api case final current?) {
        _pushRegistration = PushRegistration(push, current);
      }
    }
    return _pushRegistration != null;
  }

  /// Revoked or replaced: nothing works with this key any more.
  Future<void> _forgetRevokedKey() => _forget(
    'The server no longer accepts this client key. '
    'Set it up again with a new key.',
  );

  Future<void> _forget(String? reason) async {
    await _pushRegistration?.dispose();
    await _store.clear();
    _api = null;
    _pushRegistration = null;
    credentials = null;
    registration = null;
    events = const [];
    filter = InboxFilter.none;
    _producers.clear();
    unreadCount = null;
    _nextCursor = null;
    _inboxGeneration++;
    inboxLoaded = false;
    loadingMore = false;
    loadMoreError = null;
    savingPushPreferences = false;
    _eventToOpen = null;
    pushStatus = _initialPushStatus;
    error = reason;
    serverUnreachable = false;
    _setPhase(ConnectionPhase.disconnected);
  }

  void _onNotice(PushNotice notice) {
    // A push is a signal to look: the inbox is re-read from the server, so a
    // push delivered twice (delivery is at least once) changes nothing.
    if (notice.opened && notice.eventId != null) {
      _eventToOpen = notice.eventId;
      notifyListeners();
    }
    if (phase == ConnectionPhase.connected) unawaited(_reload());
  }

  /// Re-reads the inbox when the app returns to the foreground: pushes
  /// received in the background reach only the system tray, not the app.
  void resumed() {
    if (phase == ConnectionPhase.connected) unawaited(_reload());
  }

  void _setPhase(ConnectionPhase next) {
    phase = next;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_notices?.cancel());
    unawaited(_pushRegistration?.dispose());
    super.dispose();
  }
}
