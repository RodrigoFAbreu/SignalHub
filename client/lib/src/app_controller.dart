import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api/signalhub_api.dart';
import 'connection/server_credentials.dart';
import 'models/client_registration.dart';
import 'models/event.dart';
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

/// The app's state: the server connection, this installation's registration
/// and push status, and the inbox. The UI only renders it.
class AppController extends ChangeNotifier {
  AppController({
    required this._store,
    required this._apiFactory,
    PushService? push,
  }) : _push = push {
    _notices = push?.notices.listen(_onNotice);
  }

  /// Events per inbox page.
  static const pageSize = 30;

  final CredentialsStore _store;
  final ApiFactory _apiFactory;
  final PushService? _push;
  StreamSubscription<PushNotice>? _notices;

  SignalHubApi? _api;
  PushRegistration? _pushRegistration;

  ConnectionPhase phase = ConnectionPhase.starting;
  ServerCredentials? credentials;
  ClientRegistration? registration;
  late PushStatus pushStatus = _initialPushStatus;

  PushStatus get _initialPushStatus =>
      _push == null ? PushStatus.unavailable : PushStatus.pending;

  /// Why the last refresh or setup failed, for the owner; `null` if it
  /// worked.
  String? error;

  /// The inbox: the events read so far, newest first.
  List<Event> events = const [];

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

  /// The producers of the events in the inbox, by name. Client keys cannot
  /// list producers, so these are the ones the owner can mute by name.
  List<EventProducer> get inboxProducers {
    final byId = {for (final e in events.reversed) e.producer.id: e.producer};
    return byId.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

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
    try {
      registration = await api.getClient();
    } on ApiException catch (e) {
      return e.message;
    }
    await _store.save(parsed);
    _open(parsed);
    error = null;
    _setPhase(ConnectionPhase.connected);
    await refresh(includeClient: false);
    return null;
  }

  /// Re-reads the registration and the newest page of the inbox, and
  /// registers the push token again (pull to refresh).
  Future<void> refresh({bool includeClient = true}) async {
    if (await _reload(includeClient: includeClient)) await _registerPush();
  }

  /// Returns whether the server still accepts the key.
  Future<bool> _reload({bool includeClient = true}) async {
    final api = _api;
    if (api == null) return false;
    try {
      if (includeClient) registration = await api.getClient();
      final generation = ++_inboxGeneration;
      final page = await api.listEvents(limit: pageSize);
      final unread = await api.unreadCount();
      if (generation == _inboxGeneration) {
        _showFirstPage(page);
        unreadCount = unread;
      }
      error = null;
    } on UnauthorizedException {
      await _forgetRevokedKey();
      return false;
    } on ApiException catch (e) {
      error = e.message;
    }
    notifyListeners();
    return true;
  }

  void _showFirstPage(EventPage page) {
    events = page.items;
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
    loadingMore = true;
    loadMoreError = null;
    notifyListeners();
    try {
      final page = await api.listEvents(limit: pageSize, cursor: cursor);
      if (generation == _inboxGeneration) {
        events = [...events, ...page.items];
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

  /// The event with [id]: from the inbox if it is there, otherwise from the
  /// server. Throws an [ApiException] if it cannot be read.
  Future<Event> event(String id) async {
    if (_eventWithId(id) case final event?) return event;
    final api = _api;
    if (api == null) throw const ApiException('Not connected to a server');
    return api.getEvent(id);
  }

  /// Marks the event with [id] read, for every client of the owner, when the
  /// owner opens it. Returns the event as the server returned it, or `null`
  /// if marking failed. Failing is harmless: the event stays unread and is
  /// marked again the next time it is opened.
  Future<Event?> markRead(String id) async {
    if (_eventWithId(id) case final event? when event.isRead) return event;
    return (await setRead(id, read: true)).event;
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
  /// since stay unread, so nothing the owner has not seen is marked. Returns
  /// an error message, or `null` on success.
  Future<String?> markAllRead() async {
    final newest = events.firstOrNull;
    if (newest == null) return null;
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
    final registration = _pushRegistration;
    if (registration == null) return;
    pushStatus = await registration.register();
    notifyListeners();
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
