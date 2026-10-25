import 'dart:async';

import 'package:flutter/foundation.dart';

import 'alert/alert_controller.dart';
import 'alert/alert_platform.dart';
import 'api/signalhub_api.dart';
import 'api_gateway.dart';
import 'build_identity.dart';
import 'connection/pairing_uri.dart';
import 'connection/server_credentials.dart';
import 'connection/setup_failure.dart';
import 'features/answer_outcome.dart';
import 'features/devices_controller.dart';
import 'features/own_producers_controller.dart';
import 'features/people_controller.dart';
import 'features/producers_controller.dart';
import 'models/client_registration.dart';
import 'models/event.dart';
import 'models/inbox_filter.dart';
import 'models/push_config.dart';
import 'models/question.dart';
import 'models/users.dart';
import 'onboarding/onboarding_store.dart';
import 'push/event_notifications.dart';
import 'push/push_registration.dart';
import 'push/push_service.dart';
import 'settings/settings_groups.dart';

enum ConnectionPhase {
  /// Reading saved credentials.
  starting,

  /// No server configured: the setup screen.
  disconnected,

  /// Credentials saved and accepted by the server at least once.
  connected,
}

/// The top-level screens the bottom bar switches between. People is an
/// admin's tab.
enum HomeTab { inbox, producers, people, settings }

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
class AppController extends ChangeNotifier implements ApiGateway {
  /// [push] is the push service the build set up with its own options.
  /// Without one, [startServedPush] sets push up with the options the server
  /// serves; the build's own options take precedence. [alertPlatform] plays
  /// SignalHub's own alert; without one (iOS, tests) there are no alert
  /// settings. [openGroups] keeps which groups of the Settings screen are
  /// open; without one, they are kept only while the app runs. [onboarding]
  /// keeps whether the welcome and the _What's new_ card were said; without
  /// one the app says neither. [removeNotification] takes an answered
  /// question's notification off this device; without one (iOS, tests) it
  /// stays.
  AppController({
    required this._store,
    required this._apiFactory,
    required this._redeemPairing,
    PushService? push,
    ServedPushStarter? startServedPush,
    this.build = BuildIdentity.compiled,
    AlertPlatform? alertPlatform,
    OpenGroupsStore? openGroups,
    OnboardingStore? onboarding,
    this._removeNotification,
  }) : _push = push,
       _openGroupsStore = openGroups,
       _onboardingStore = onboarding,
       alert = alertPlatform == null ? null : AlertController(alertPlatform),
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
  final OpenGroupsStore? _openGroupsStore;
  final OnboardingStore? _onboardingStore;
  final NotificationRemover? _removeNotification;
  StreamSubscription<PushNotice>? _notices;
  final _questionEnds = StreamController<String>.broadcast();

  /// The data-only notices that a question was answered or closed, or its
  /// event deleted (docs/design/answers/API-PROPOSAL.md, section 6).
  static const _endingNotices = {'answered', 'closed', 'deleted'};

  /// The IDs of events whose question a notice says ended (answered, closed,
  /// or the event deleted), as the notices arrive with the app open: an open
  /// event screen reads its event again.
  Stream<String> get questionEnds => _questionEnds.stream;

  /// The served options push was set up with; `null` until then.
  PushConfig? _servedPushConfig;
  Future<PushService?>? _startingServedPush;

  /// Which SignalHub build this app is.
  final BuildIdentity build;

  /// This installation's alert settings, which belong to the device and not
  /// to the server connection; `null` where the platform plays no alert of
  /// SignalHub's own.
  final AlertController? alert;

  /// The groups of the Settings screen the owner left open; they belong to
  /// the device, like [alert], and stay when it disconnects.
  Set<SettingsGroup> openSettingsGroups = {};

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

  /// Whether the app is at setup because the server stopped accepting this
  /// device (any `401`): setup says so in one neutral sentence. A new
  /// connection, or disconnecting on purpose, clears it.
  bool signedOut = false;

  /// What this device still has to say to its owner, once: the welcome after
  /// connecting, or _What's new_ on a device that was connected before the
  /// app updated.
  OnboardingStep onboarding = OnboardingStep.done;

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

  /// How many open questions this person may answer; the inbox's _To answer_
  /// chip and the dot on its tab.
  int toAnswerCount = 0;

  /// Whether the first page of the inbox has been read since connecting.
  bool inboxLoaded = false;

  /// When the first page of the inbox was last read; `null` until it was.
  DateTime? inboxLoadedAt;

  /// Whether an older page is being read.
  bool loadingMore = false;

  /// Why reading an older page failed; `null` if it worked.
  String? loadMoreError;

  String? _nextCursor;

  /// The last event of the newest-first pages read so far, before the filter
  /// dropped any. An event the app changes is listed again only if it is not
  /// older than this: an older one comes with a later page.
  Event? _lastRead;

  /// Counts inbox reloads, so an older page requested before a reload is not
  /// appended after it.
  int _inboxGeneration = 0;

  /// The event of a notification the owner tapped, until the inbox opens it.
  String? _eventToOpen;

  /// Whether the owner tapped a notice about a device, until the inbox opens
  /// the devices.
  bool _deviceNoticeToOpen = false;

  /// Whether a change to the push preferences is being saved.
  bool savingPushPreferences = false;

  @override
  UserRole get role => registration?.role ?? UserRole.basic;

  @override
  String? get userId => registration?.user?.id;

  @override
  String? get userName => registration?.user?.name;

  /// The tab of the bottom bar that is showing. Kept here so a screen can send
  /// the person to another tab (the welcome's _Find producers_).
  HomeTab tab = HomeTab.inbox;

  /// The tabs the bottom bar offers this role, in order.
  List<HomeTab> get tabs => [
    HomeTab.inbox,
    HomeTab.producers,
    if (role.isAdmin) HomeTab.people,
    HomeTab.settings,
  ];

  void selectTab(HomeTab next) {
    if (tab == next) return;
    tab = next;
    notifyListeners();
  }

  /// The producers this user sees, and subscribing to them.
  late ProducersController producers = ProducersController(this);

  /// The producers this user owns, their keys and who may see them.
  late OwnProducersController ownProducers = OwnProducersController(this);

  /// The people on the server; for an admin, their roles and devices.
  late PeopleController people = PeopleController(this);

  /// The devices this role may list and manage, and connecting new ones.
  late DevicesController deviceList = _newDeviceList();

  /// How this user's role changed under them since the app last said so; `null`
  /// when nothing is to be said. The app learns of a change when a request is
  /// refused or when it reads the registration again, never by push.
  ({UserRole from, UserRole to})? _roleChange;

  /// The role change to tell the person about, once.
  ({UserRole from, UserRole to})? takeRoleChange() {
    final change = _roleChange;
    _roleChange = null;
    return change;
  }

  /// Whether a role change is waiting to be said.
  bool get hasRoleChange => _roleChange != null;

  /// Keeps [next] as this installation's registration, and notes a change of
  /// the user's role since the one kept before.
  void _setRegistration(ClientRegistration next) {
    final before = registration?.role;
    registration = next;
    if (before != null && before != next.role) {
      _roleChange = (from: before, to: next.role);
    }
  }

  /// Reads the registration again, so a role the host or an admin changed is
  /// noticed; a failure leaves what is known.
  Future<void> rereadRegistration() async {
    final api = _api;
    if (api == null) return;
    try {
      _setRegistration(await api.getClient());
    } on UnauthorizedException {
      await _forgetRevokedKey();
      return;
    } on ApiException catch (e) {
      debugPrint('Registration not re-read: ${e.message}');
    }
    notifyListeners();
  }

  @override
  Future<T> call<T>(Future<T> Function(SignalHubApi api) call) async {
    final api = _api;
    if (api == null) throw const SignedOutException();
    try {
      return await call(api);
    } on UnauthorizedException {
      await _forgetRevokedKey();
      throw const SignedOutException();
    } on ApiException catch (e) {
      // A role that no longer allows it: read it again, so the screens
      // follow the new role.
      if (e.statusCode == 403) await rereadRegistration();
      rethrow;
    }
  }

  /// Whether the server has events older than [events].
  bool get hasMore => _nextCursor != null;

  /// The producers of the events the inbox has read since connecting, by id:
  /// names for a producer the user no longer sees, such as one a filter or a
  /// muted list still names.
  final _producers = <String, EventProducer>{};

  /// The name of the producer with [id], from the producers this user sees or
  /// else from an event the inbox has read; `null` if neither knows it.
  String? producerName(String id) =>
      producers.byId(id)?.name ?? _producers[id]?.name;

  /// Whether _Mark all as read_ can be offered: it marks every unread event
  /// up to the newest one shown, so not while the filter hides some of them.
  bool get canMarkAllRead => !filter.narrowsEvents;

  /// Loads saved credentials and, if there are any, connects.
  Future<void> start() async {
    await alert?.load();
    await _loadOpenSettingsGroups();
    final saved = await _store.load();
    if (saved == null) {
      _eventToOpen = null;
      _deviceNoticeToOpen = false;
      _setPhase(ConnectionPhase.disconnected);
      return;
    }
    _open(saved);
    await _loadOnboarding();
    _setPhase(ConnectionPhase.connected);
    await refresh();
  }

  /// A device that starts with saved credentials and no record was connected
  /// before the app kept one: it gets _What's new_ once.
  Future<void> _loadOnboarding() async {
    final store = _onboardingStore;
    if (store == null) return;
    try {
      onboarding = await store.load() ?? OnboardingStep.whatsNew;
    } on Exception catch (e) {
      debugPrint('Onboarding step not read: ${e.runtimeType}');
    }
  }

  /// Ends the welcome: [findProducers] opens the Producers tab, otherwise the
  /// inbox shows.
  Future<void> finishWelcome({bool findProducers = false}) async {
    if (onboarding != OnboardingStep.welcome) return;
    if (findProducers) tab = HomeTab.producers;
    await _finishOnboarding();
  }

  /// Dismisses _What's new_ for good; [seeProducers] first opens the
  /// Producers tab.
  Future<void> dismissWhatsNew({bool seeProducers = false}) async {
    if (onboarding != OnboardingStep.whatsNew) return;
    if (seeProducers) tab = HomeTab.producers;
    await _finishOnboarding();
  }

  Future<void> _finishOnboarding() async {
    onboarding = OnboardingStep.done;
    notifyListeners();
    try {
      await _onboardingStore?.save(OnboardingStep.done);
    } on Exception catch (e) {
      debugPrint('Onboarding step not saved: ${e.runtimeType}');
    }
  }

  Future<void> _loadOpenSettingsGroups() async {
    try {
      openSettingsGroups = await _openGroupsStore?.load() ?? {};
    } on Exception catch (e) {
      debugPrint('Open settings groups not read: ${e.runtimeType}');
    }
  }

  /// Notes that the owner opened or folded [group], for the next time the
  /// Settings screen opens. Not being saved changes nothing else.
  Future<void> setSettingsGroupOpen(
    SettingsGroup group, {
    required bool open,
  }) async {
    openSettingsGroups = {
      for (final g in openSettingsGroups)
        if (g != group) g,
      if (open) group,
    };
    try {
      await _openGroupsStore?.save(openSettingsGroups);
    } on Exception catch (e) {
      debugPrint('Open settings groups not saved: ${e.runtimeType}');
    }
  }

  /// Connects to a server with a client key typed by the owner. Saves them
  /// only once the server accepts the key. Returns why it failed, or `null`
  /// on success.
  Future<SetupFailure?> connect(String serverUrl, String clientKey) async {
    final ServerCredentials parsed;
    try {
      parsed = ServerCredentials.parse(serverUrl, clientKey);
    } on FormatException catch (e) {
      final badAddress = ServerCredentials.parseServerUrl(serverUrl) == null;
      return SetupFailure(
        badAddress ? SetupFailureKind.badAddress : SetupFailureKind.badKey,
        e.message,
      );
    }
    final api = _apiFactory(parsed);
    final ClientRegistration accepted;
    try {
      accepted = await api.getClient();
    } on UnauthorizedException {
      return SetupFailure.keyRejected;
    } on ApiException catch (e) {
      return _failure(e, parsed.baseUrl);
    }
    await _connected(parsed, accepted);
    return null;
  }

  /// Registers this installation with a pairing code the owner scanned or
  /// pasted ([PairingUri]), and connects with the client key it returns.
  /// Returns why it failed, or `null` on success.
  Future<SetupFailure?> pair(String pairingUri) async {
    final PairingUri parsed;
    try {
      parsed = PairingUri.parse(pairingUri);
    } on FormatException {
      return PairingUri.isWebSignIn(pairingUri)
          ? SetupFailure.webSignIn
          : SetupFailure.notInvitation;
    }
    final PairedClient paired;
    final ServerCredentials credentials;
    try {
      paired = await _redeemPairing(parsed.serverUrl, parsed.code);
      credentials = ServerCredentials.parse(parsed.serverUrl, paired.clientKey);
    } on PairingRejectedException {
      return const SetupFailure(
        SetupFailureKind.codeRejected,
        'This pairing code has expired or was already used. '
        'Ask for a new one.',
      );
    } on ApiException catch (e) {
      return _failure(e, parsed.serverUrl);
    } on FormatException {
      return SetupFailure.unexpectedAnswer;
    }
    await _connected(credentials, paired.registration);
    return null;
  }

  /// A failed request of setup. An unreachable server is named by its
  /// address, as the code or the owner gave it.
  static SetupFailure _failure(ApiException e, String serverUrl) =>
      e.statusCode == null
      ? SetupFailure.unreachable(Uri.tryParse(serverUrl)?.authority ?? '')
      : SetupFailure.serverProblem;

  /// Saves credentials the server has accepted and shows the inbox. A
  /// connection made in this version of the app gets the welcome, and so no
  /// _What's new_ later.
  Future<void> _connected(
    ServerCredentials accepted,
    ClientRegistration client,
  ) async {
    registration = client;
    _roleChange = null;
    await _store.save(accepted);
    _open(accepted);
    error = null;
    signedOut = false;
    await _startOnboarding();
    _setPhase(ConnectionPhase.connected);
    await refresh(includeClient: false);
  }

  Future<void> _startOnboarding() async {
    final store = _onboardingStore;
    if (store == null) return;
    onboarding = OnboardingStep.welcome;
    try {
      await store.save(OnboardingStep.welcome);
    } on Exception catch (e) {
      debugPrint('Onboarding step not saved: ${e.runtimeType}');
    }
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
      if (includeClient) _setRegistration(await api.getClient());
      final generation = ++_inboxGeneration;
      final filter = this.filter;
      final page = await api.listEvents(limit: pageSize, filter: filter);
      final counts = await api.eventCounts();
      if (generation == _inboxGeneration) {
        _showFirstPage(page, filter);
        _setCounts(counts);
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
    _lastRead = page.items.lastOrNull;
    inboxLoaded = true;
    inboxLoadedAt = DateTime.now();
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
        _lastRead = page.items.lastOrNull ?? _lastRead;
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
  /// before the `read` filter ignores it. The same rule applies when the app
  /// changes an event ([_replaceEvent]).
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
    _lastRead = null;
    inboxLoaded = false;
    inboxLoadedAt = null;
    loadMoreError = null;
    notifyListeners();
    await _reload(includeClient: false);
  }

  /// Shows every event again.
  Future<void> clearFilter() => setFilter(InboxFilter.none);

  /// The event with [id]: from the inbox if it is there, otherwise from the
  /// server. Throws an [ApiException] if it cannot be read: an
  /// [EventNotFoundException] when it is not in this user's inbox any more
  /// (deleted, or its producer unsubscribed), which also takes it out of the
  /// inbox list.
  Future<Event> event(String id) async {
    if (_eventWithId(id) case final event?) return event;
    try {
      return await call((api) => api.getEvent(id));
    } on EventNotFoundException {
      await _removeEvent(id);
      rethrow;
    }
  }

  /// Takes the event with [id] out of the inbox, which the server can no
  /// longer read it from.
  Future<void> _removeEvent(String id) async {
    if (_eventWithId(id) == null) return;
    events = [
      for (final e in events)
        if (e.id != id) e,
    ];
    notifyListeners();
    try {
      await _readUnreadCount();
    } on UnauthorizedException {
      await _forgetRevokedKey();
      return;
    }
    notifyListeners();
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
      try {
        final event = await (read ? api.markRead(id) : api.markUnread(id));
        _replaceEvent(event);
        changed = event;
      } on EventNotFoundException {
        await _removeEvent(id);
        rethrow;
      }
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
      final read = [for (final e in events) e.isRead ? e : e.withReadAt(now)];
      events = read.where(filter.admits).toList(growable: false);
      // Everything at or before the newest event is read, so no older page
      // has an unread event left to bring.
      if (filter.unreadOnly) _nextCursor = null;
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
      _setCounts(await api.eventCounts());
    } on UnauthorizedException {
      rethrow;
    } on ApiException catch (e) {
      debugPrint('Unread count not updated: ${e.message}');
    }
  }

  void _setCounts(EventCounts counts) {
    unreadCount = counts.unread;
    toAnswerCount = counts.toAnswer;
  }

  /// Reads the event with [id] from the server again, for a card that may
  /// have gone stale (the app came back, or a `409` said so), and shows it in
  /// the inbox. An [EventNotFoundException] takes it out of the inbox.
  Future<Event> reloadEvent(String id) async {
    final Event fresh;
    try {
      fresh = await call((api) => api.getEvent(id));
    } on EventNotFoundException {
      await _removeEvent(id);
      rethrow;
    }
    if (_eventWithId(id) != null) _replaceEvent(fresh);
    unawaited(_readCountsQuietly());
    return fresh;
  }

  Future<void> _readCountsQuietly() async {
    try {
      await _readUnreadCount();
    } on UnauthorizedException {
      await _forgetRevokedKey();
      return;
    }
    notifyListeners();
  }

  /// Sends this person's answer to the event's question. The inbox follows
  /// what the server decided, and the counts are read again.
  Future<AnswerOutcome> answerEvent(
    String id, {
    List<String> choices = const [],
    String? text,
  }) async {
    final api = _api;
    if (api == null) return const AnswerFailed('Not connected to a server');
    AnswerOutcome outcome;
    try {
      final answer = await api.answerEvent(id, choices: choices, text: text);
      outcome = AnswerAccepted(
        QuestionState(state: AnswerState.answered, answer: answer),
      );
      // The server sends its notice to every other device, not this one,
      // however the question was opened here.
      unawaited(_removeNotification?.call(id));
    } on QuestionConflictException catch (e) {
      outcome = AnswerRefused(e.state);
    } on EventNotFoundException {
      await _removeEvent(id);
      return const AnswerGone();
    } on UnauthorizedException {
      await _forgetRevokedKey();
      return const AnswerFailed('This device is no longer connected');
    } on ApiException catch (e) {
      if (e.statusCode != 403) return AnswerFailed(e.message);
      // A refusal may be "not allowed" or something else: read it again.
      try {
        final fresh = await reloadEvent(id);
        return AnswerNotAllowed(fresh);
      } on EventNotFoundException {
        return const AnswerGone();
      } on ApiException catch (_) {
        return AnswerFailed(e.message);
      }
    }
    final state = switch (outcome) {
      AnswerAccepted(:final state) || AnswerRefused(:final state) => state,
      _ => null,
    };
    final shown = _eventWithId(id);
    if (state != null && shown != null) {
      _replaceEvent(shown.withQuestionState(state));
    }
    await _readCountsQuietly();
    return outcome;
  }

  Event? _eventWithId(String id) => events.where((e) => e.id == id).firstOrNull;

  /// Shows [updated] as the server returned it, as the filter allows: an
  /// event it no longer admits (read, under unread only) leaves the list, and
  /// one it admits again (unread) returns in its newest-first place, unless
  /// that is beyond the pages read, which bring it themselves.
  void _replaceEvent(Event updated) {
    final others = [
      for (final e in events)
        if (e.id != updated.id) e,
    ];
    if (!filter.admits(updated)) {
      events = others;
      return;
    }
    final index = events.indexWhere((e) => e.id == updated.id);
    if (index >= 0) {
      events = [...events]..[index] = updated;
    } else if (_nextCursor == null || _notAfterLastRead(updated)) {
      final at = others.indexWhere((e) => _isNewer(updated, e));
      events = others..insert(at < 0 ? others.length : at, updated);
    }
  }

  bool _notAfterLastRead(Event event) {
    final last = _lastRead;
    return last != null && !_isNewer(last, event);
  }

  /// Whether [a] comes before [b] in the listing's order: `createdAt`, then
  /// `id`, both descending.
  static bool _isNewer(Event a, Event b) {
    final byTime = a.createdAt.compareTo(b.createdAt);
    return byTime != 0 ? byTime > 0 : a.id.compareTo(b.id) > 0;
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
      _setRegistration(await api.setPushPreferences(preferences));
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
    await _forget(signedOut: false);
  }

  /// Whether the owner tapped a notice about a device, once: the inbox opens
  /// the devices.
  bool takeDeviceNoticeToOpen() {
    final open = _deviceNoticeToOpen;
    _deviceNoticeToOpen = false;
    return open;
  }

  void _open(ServerCredentials saved) {
    credentials = saved;
    _api = _apiFactory(saved);
    _resetFeatures();
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

  /// Revoked or replaced, or its person removed: any `401` means nothing works
  /// with this key any more, and the server cannot say which.
  Future<void> _forgetRevokedKey() => _forget(signedOut: true);

  /// Returns to setup. The state is dropped, and setup shown, before anything
  /// is awaited, so no frame shows the old content.
  Future<void> _forget({required bool signedOut}) async {
    final pushRegistration = _pushRegistration;
    _api = null;
    _pushRegistration = null;
    credentials = null;
    registration = null;
    events = const [];
    filter = InboxFilter.none;
    _producers.clear();
    unreadCount = null;
    toAnswerCount = 0;
    _nextCursor = null;
    _lastRead = null;
    _inboxGeneration++;
    inboxLoaded = false;
    inboxLoadedAt = null;
    loadingMore = false;
    loadMoreError = null;
    savingPushPreferences = false;
    _eventToOpen = null;
    _deviceNoticeToOpen = false;
    _roleChange = null;
    onboarding = OnboardingStep.done;
    tab = HomeTab.inbox;
    _resetFeatures();
    pushStatus = _initialPushStatus;
    error = null;
    this.signedOut = signedOut;
    serverUnreachable = false;
    _setPhase(ConnectionPhase.disconnected);
    await pushRegistration?.dispose();
    await _store.clear();
  }

  /// The clock the people, devices and event screens read (countdowns, when a
  /// device was last active, when a question closes); tests replace it.
  DateTime Function() clock = DateTime.now;

  DevicesController _newDeviceList() => DevicesController(
    this,
    thisDeviceId: () => registration?.id,
    now: () => clock(),
  );

  void _resetFeatures() {
    producers.dispose();
    ownProducers.dispose();
    people.dispose();
    deviceList.dispose();
    producers = ProducersController(this);
    ownProducers = OwnProducersController(this);
    people = PeopleController(this);
    deviceList = _newDeviceList();
  }

  void _onNotice(PushNotice notice) {
    // A push is a signal to look: the inbox is re-read from the server, so a
    // push delivered twice (delivery is at least once) changes nothing.
    if (notice.opened && notice.eventId != null) {
      _eventToOpen = notice.eventId;
      notifyListeners();
    } else if (notice.opened && notice.notice != null) {
      // A notice is about a device and has no event: it opens the devices.
      _deviceNoticeToOpen = true;
      notifyListeners();
    }
    if (_endingNotices.contains(notice.notice) && notice.eventId != null) {
      _questionEnds.add(notice.eventId!);
    }
    if (phase == ConnectionPhase.connected) unawaited(_reload());
  }

  /// Re-reads the inbox when the app returns to the foreground: pushes
  /// received in the background reach only the system tray, not the app.
  void resumed() {
    if (phase == ConnectionPhase.connected) unawaited(_reload());
  }

  /// Re-reads the inbox and the unread count, after a change elsewhere (a
  /// subscription, events marked read in a producer's own list) altered what
  /// they hold.
  Future<void> reloadInbox() => _reload(includeClient: false);

  void _setPhase(ConnectionPhase next) {
    phase = next;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_notices?.cancel());
    unawaited(_questionEnds.close());
    unawaited(_pushRegistration?.dispose());
    alert?.dispose();
    producers.dispose();
    ownProducers.dispose();
    people.dispose();
    deviceList.dispose();
    super.dispose();
  }
}
