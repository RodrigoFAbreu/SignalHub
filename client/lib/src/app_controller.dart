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
/// and push status, and recent pushes. The UI only renders it.
class AppController extends ChangeNotifier {
  AppController({
    required this._store,
    required this._apiFactory,
    PushService? push,
  }) : _push = push {
    _notices = push?.notices.listen(_onNotice);
  }

  /// How many received pushes the home screen keeps.
  static const maxNotices = 20;

  final CredentialsStore _store;
  final ApiFactory _apiFactory;
  final PushService? _push;
  StreamSubscription<PushNotice>? _notices;

  SignalHubApi? _api;
  PushRegistration? _pushRegistration;

  ConnectionPhase phase = ConnectionPhase.starting;
  ServerCredentials? credentials;
  ClientRegistration? registration;
  Event? latestEvent;
  late PushStatus pushStatus = _initialPushStatus;

  PushStatus get _initialPushStatus =>
      _push == null ? PushStatus.unavailable : PushStatus.pending;

  /// Why the last refresh or setup failed, for the owner; `null` if it
  /// worked.
  String? error;

  /// Pushes received since the app started, newest first, one per event.
  final List<PushNotice> notices = [];

  /// Loads saved credentials and, if there are any, connects.
  Future<void> start() async {
    final saved = await _store.load();
    if (saved == null) {
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

  /// Re-reads the registration and the latest event, and registers the push
  /// token again (pull to refresh).
  Future<void> refresh({bool includeClient = true}) async {
    if (await _reload(includeClient: includeClient)) await _registerPush();
  }

  /// Returns whether the server still accepts the key.
  Future<bool> _reload({bool includeClient = true}) async {
    final api = _api;
    if (api == null) return false;
    try {
      if (includeClient) registration = await api.getClient();
      latestEvent = (await api.listEvents(limit: 1)).items.firstOrNull;
      error = null;
    } on UnauthorizedException {
      // Revoked or replaced: nothing works with this key any more.
      await _forget(
        'The server no longer accepts this client key. '
        'Set it up again with a new key.',
      );
      return false;
    } on ApiException catch (e) {
      error = e.message;
    }
    notifyListeners();
    return true;
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

  Future<void> _forget(String? reason) async {
    await _pushRegistration?.dispose();
    await _store.clear();
    _api = null;
    _pushRegistration = null;
    credentials = null;
    registration = null;
    latestEvent = null;
    notices.clear();
    pushStatus = _initialPushStatus;
    error = reason;
    _setPhase(ConnectionPhase.disconnected);
  }

  void _onNotice(PushNotice notice) {
    // Delivery is at least once, so the same event may arrive again.
    final eventId = notice.eventId;
    if (eventId != null && notices.any((n) => n.eventId == eventId)) return;
    notices.insert(0, notice);
    if (notices.length > maxNotices) notices.removeLast();
    notifyListeners();
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
