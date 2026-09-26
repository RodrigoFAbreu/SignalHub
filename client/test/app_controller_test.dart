import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/app_controller.dart';
import 'package:signalhub_client/src/connection/server_credentials.dart';
import 'package:signalhub_client/src/models/client_registration.dart';
import 'package:signalhub_client/src/push/push_registration.dart';
import 'package:signalhub_client/src/push/push_service.dart';

import 'support/fakes.dart';

void main() {
  late FakeBackend backend;
  late FakePushService push;
  late InMemoryCredentialsStore store;

  setUp(() {
    backend = FakeBackend();
    push = FakePushService();
    store = InMemoryCredentialsStore();
  });

  AppController controller({bool withPush = true}) => AppController(
    store: store,
    apiFactory: (credentials) =>
        backend.api(credentials.baseUrl, credentials.clientKey),
    push: withPush ? push : null,
  );

  test('starts on setup without saved credentials', () async {
    final app = controller();

    await app.start();

    expect(app.phase, ConnectionPhase.disconnected);
    expect(backend.requests, isEmpty);
  });

  test('connecting saves the credentials and registers for push', () async {
    backend.publish('e-1', 'Build failed');
    final app = controller();

    final error = await app.connect(serverUrl, clientKey);

    expect(error, isNull);
    expect(app.phase, ConnectionPhase.connected);
    expect(store.saved?.clientKey, clientKey);
    expect(app.registration?.name, 'Pixel 8');
    expect(app.inboxLoaded, isTrue);
    expect(app.events.single.title, 'Build failed');
    expect(app.pushStatus, PushStatus.registered);
    // The backend knows the target by the push service's provider name.
    expect(backend.pushTarget?['provider'], 'fake');
    expect(backend.pushToken, 'device-token-1');
  });

  test('a rejected key is reported and not saved', () async {
    backend.acceptedKey = 'shck1_other_key';
    final app = controller();

    final error = await app.connect(serverUrl, clientKey);

    expect(error, 'The server did not accept this client key');
    expect(app.phase, isNot(ConnectionPhase.connected));
    expect(store.saved, isNull);
  });

  test('invalid input is reported without a request', () async {
    final app = controller();

    final error = await app.connect('not a url', clientKey);

    expect(error, contains('server address'));
    expect(backend.requests, isEmpty);
  });

  test('restarts connected with saved credentials', () async {
    store.saved = ServerCredentials.parse(serverUrl, clientKey);
    final app = controller();

    await app.start();

    expect(app.phase, ConnectionPhase.connected);
    expect(app.registration?.name, 'Pixel 8');
    expect(app.pushStatus, PushStatus.registered);
  });

  test('a revoked key returns to setup and forgets the credentials', () async {
    store.saved = ServerCredentials.parse(serverUrl, clientKey);
    backend.acceptedKey = null;
    final app = controller();

    await app.start();

    expect(app.phase, ConnectionPhase.disconnected);
    expect(store.saved, isNull);
    expect(app.error, contains('no longer accepts'));
  });

  test('an unreachable server keeps the credentials and reports it', () async {
    store.saved = ServerCredentials.parse(serverUrl, clientKey);
    backend.offline = true;
    final app = controller();

    await app.start();

    expect(app.phase, ConnectionPhase.connected);
    expect(store.saved, isNotNull);
    expect(app.error, 'Could not reach the server');

    backend.offline = false;
    await app.refresh();
    expect(app.error, isNull);
    expect(app.registration?.name, 'Pixel 8');
  });

  test('denied notification permission registers no target', () async {
    push.permitted = false;
    final app = controller();

    await app.connect(serverUrl, clientKey);

    expect(app.pushStatus, PushStatus.permissionDenied);
    expect(backend.pushTarget, isNull);
  });

  test('a provider without a token reports a failed registration', () async {
    push.token = null;
    final app = controller();

    await app.connect(serverUrl, clientKey);

    expect(app.pushStatus, PushStatus.failed);
    expect(backend.pushTarget, isNull);
  });

  test('a build without push works and says so', () async {
    final app = controller(withPush: false);

    await app.connect(serverUrl, clientKey);

    expect(app.phase, ConnectionPhase.connected);
    expect(app.pushStatus, PushStatus.unavailable);
    expect(backend.pushTarget, isNull);
  });

  test('a refreshed token replaces the push target', () async {
    final app = controller();
    await app.connect(serverUrl, clientKey);

    push.refreshes.add('device-token-2');
    await pumpEventQueue();

    expect(backend.pushToken, 'device-token-2');
    app.dispose();
  });

  test('a push re-reads the inbox from the server', () async {
    final app = controller();
    await app.connect(serverUrl, clientKey);
    expect(app.events, isEmpty);
    backend.publish('e-1', 'First');

    push.received
      ..add(const PushNotice(title: 'First', eventId: 'e-1'))
      // At-least-once delivery: the same event again changes nothing.
      ..add(const PushNotice(title: 'First', eventId: 'e-1'));
    await pumpEventQueue();

    expect(app.events.map((e) => e.id), ['e-1']);
    expect(app.takeEventToOpen(), isNull);
  });

  test('returning to the foreground re-reads the inbox', () async {
    final app = controller();
    await app.connect(serverUrl, clientKey);
    // Pushed while in the background: only the system tray saw it.
    backend.publish('e-1', 'First');

    app.resumed();
    await pumpEventQueue();

    expect(app.events.map((e) => e.id), ['e-1']);
    expect(app.unreadCount, 1);
  });

  test('returning to the foreground without a server reads nothing', () async {
    final app = controller();
    await app.start();

    app.resumed();
    await pumpEventQueue();

    expect(backend.requests, isEmpty);
  });

  test('a tapped notification asks the inbox to open its event', () async {
    final app = controller();
    await app.connect(serverUrl, clientKey);

    push.received.add(
      const PushNotice(title: 'First', eventId: 'e-1', opened: true),
    );
    await pumpEventQueue();

    expect(app.takeEventToOpen(), 'e-1');
    // Only once.
    expect(app.takeEventToOpen(), isNull);
  });

  test('the notification that started the app waits for the inbox', () async {
    store.saved = ServerCredentials.parse(serverUrl, clientKey);
    final app = controller();
    push.received.add(
      const PushNotice(title: 'First', eventId: 'e-1', opened: true),
    );
    await pumpEventQueue();

    await app.start();

    expect(app.takeEventToOpen(), 'e-1');
  });

  test('pages through the inbox, newest first', () async {
    for (var i = 1; i <= AppController.pageSize + 5; i++) {
      backend.publish('e-$i', 'Event $i');
    }
    final app = controller();
    await app.connect(serverUrl, clientKey);

    expect(app.events, hasLength(AppController.pageSize));
    expect(app.events.first.id, 'e-${AppController.pageSize + 5}');
    expect(app.hasMore, isTrue);

    await app.loadMore();

    expect(app.events, hasLength(AppController.pageSize + 5));
    expect(app.events.last.id, 'e-1');
    expect(app.hasMore, isFalse);
    expect(app.loadingMore, isFalse);
  });

  test('a failed older page is reported and can be retried', () async {
    for (var i = 1; i <= AppController.pageSize + 1; i++) {
      backend.publish('e-$i', 'Event $i');
    }
    final app = controller();
    await app.connect(serverUrl, clientKey);
    backend.offline = true;

    await app.loadMore();

    expect(app.loadMoreError, 'Could not reach the server');
    expect(app.events, hasLength(AppController.pageSize));
    expect(app.hasMore, isTrue);

    backend.offline = false;
    await app.loadMore();

    expect(app.loadMoreError, isNull);
    expect(app.events.last.id, 'e-1');
  });

  test('an older page read across a refresh is not appended', () async {
    for (var i = 1; i <= AppController.pageSize + 1; i++) {
      backend.publish('e-$i', 'Event $i');
    }
    final app = controller();
    await app.connect(serverUrl, clientKey);

    backend.holdOlderPages = Completer();
    final older = app.loadMore();
    await app.refresh();
    backend.holdOlderPages!.complete();
    await older;

    expect(app.events, hasLength(AppController.pageSize));
    expect(app.hasMore, isTrue);
    expect(app.loadingMore, isFalse);
  });

  test('opens an event from the inbox or the server', () async {
    backend.publish('e-1', 'Build failed');
    final app = controller();
    await app.connect(serverUrl, clientKey);
    backend.requests.clear();

    expect((await app.event('e-1')).title, 'Build failed');
    expect(backend.requests, isEmpty);

    backend.publish('e-2', 'Not in the inbox yet');
    expect((await app.event('e-2')).title, 'Not in the inbox yet');
    expect(backend.requests.single.url.path, '/api/v1/events/e-2');
  });

  test('reads the unread count with the inbox', () async {
    backend
      ..publish('e-1', 'Read before', readAt: '2026-09-25T12:04:00Z')
      ..publish('e-2', 'New');
    final app = controller();

    await app.connect(serverUrl, clientKey);

    expect(app.unreadCount, 1);
    expect(app.events.map((e) => e.isRead), [false, true]);

    backend.publish('e-3', 'Newer');
    await app.refresh();
    expect(app.unreadCount, 2);
  });

  test('opening an event marks it read on the server', () async {
    backend
      ..publish('e-1', 'Older')
      ..publish('e-2', 'Newer');
    final app = controller();
    await app.connect(serverUrl, clientKey);

    await app.markRead('e-1');

    expect(backend.isRead('e-1'), isTrue);
    expect(app.events.map((e) => e.isRead), [false, true]);
    expect(app.unreadCount, 1);

    // Already read: no request.
    backend.requests.clear();
    await app.markRead('e-1');
    expect(backend.requests, isEmpty);
  });

  test('an event not in the inbox is marked read by its ID', () async {
    final app = controller();
    await app.connect(serverUrl, clientKey);
    backend.publish('e-1', 'Arrived since');

    await app.markRead('e-1');

    expect(backend.isRead('e-1'), isTrue);
    expect(app.unreadCount, 0);
  });

  test('marking read that fails leaves the event unread', () async {
    backend.publish('e-1', 'Build failed');
    final app = controller();
    await app.connect(serverUrl, clientKey);
    backend.offline = true;

    await app.markRead('e-1');

    expect(app.events.single.isRead, isFalse);
    expect(app.unreadCount, 1);
    expect(app.phase, ConnectionPhase.connected);
  });

  test('marks an event unread again', () async {
    backend.publish('e-1', 'Build failed', readAt: '2026-09-25T12:04:00Z');
    final app = controller();
    await app.connect(serverUrl, clientKey);
    expect(app.unreadCount, 0);

    expect(await app.markUnread('e-1'), isNull);

    expect(backend.isRead('e-1'), isFalse);
    expect(app.events.single.isRead, isFalse);
    expect(app.unreadCount, 1);

    backend.offline = true;
    expect(await app.markUnread('e-1'), 'Could not reach the server');
  });

  test('marks all read up to the newest event shown, not newer ones', () async {
    for (var i = 1; i <= AppController.pageSize + 2; i++) {
      backend.publish('e-$i', 'Event $i');
    }
    final app = controller();
    await app.connect(serverUrl, clientKey);
    // Arrives after the inbox was read: the owner has not seen it.
    backend.publish('e-new', 'Not seen yet');

    expect(await app.markAllRead(), isNull);

    expect(app.events.every((e) => e.isRead), isTrue);
    // Older events not read into the inbox yet are read too.
    expect(backend.isRead('e-1'), isTrue);
    expect(backend.isRead('e-new'), isFalse);
    expect(app.unreadCount, 1);
  });

  test('a failed mark all read is reported', () async {
    backend.publish('e-1', 'Build failed');
    final app = controller();
    await app.connect(serverUrl, clientKey);
    backend.offline = true;

    expect(await app.markAllRead(), 'Could not reach the server');
    expect(app.events.single.isRead, isFalse);
  });

  test('a revoked key while marking read returns to setup', () async {
    backend.publish('e-1', 'Build failed');
    final app = controller();
    await app.connect(serverUrl, clientKey);
    backend.acceptedKey = null;

    await app.markRead('e-1');

    expect(app.phase, ConnectionPhase.disconnected);
    expect(app.unreadCount, isNull);
    expect(store.saved, isNull);
  });

  test('a revoked key while paging returns to setup', () async {
    for (var i = 1; i <= AppController.pageSize + 1; i++) {
      backend.publish('e-$i', 'Event $i');
    }
    final app = controller();
    await app.connect(serverUrl, clientKey);
    backend.acceptedKey = null;

    await app.loadMore();

    expect(app.phase, ConnectionPhase.disconnected);
    expect(app.events, isEmpty);
    expect(store.saved, isNull);
  });

  test('disconnecting removes the push target and the credentials', () async {
    final app = controller();
    await app.connect(serverUrl, clientKey);

    await app.disconnect();

    expect(app.phase, ConnectionPhase.disconnected);
    expect(backend.pushTarget, isNull);
    expect(push.tokenDeleted, isTrue);
    expect(store.saved, isNull);
    expect(app.error, isNull);
  });

  test('disconnecting works when the server is unreachable', () async {
    final app = controller();
    await app.connect(serverUrl, clientKey);
    backend.offline = true;

    await app.disconnect();

    expect(app.phase, ConnectionPhase.disconnected);
    expect(push.tokenDeleted, isTrue);
    expect(store.saved, isNull);
  });

  test('saves push preferences and shows what the server stored', () async {
    final app = controller();
    await app.connect(serverUrl, clientKey);

    final error = await app.setPushPreferences(
      const PushPreferences(mutedProducerIds: ['p-2', 'p-1', 'p-2']),
    );

    expect(error, isNull);
    expect(app.savingPushPreferences, isFalse);
    expect(app.registration?.pushPreferences?.mutedProducerIds, ['p-1', 'p-2']);
    expect(backend.pushPreferences?['mutedProducerIds'], ['p-1', 'p-2']);
  });

  test('a failed push preference change is reported and not shown', () async {
    final app = controller();
    await app.connect(serverUrl, clientKey);
    backend.offline = true;

    final error = await app.setPushPreferences(
      const PushPreferences(enabled: false),
    );

    expect(error, 'Could not reach the server');
    expect(app.savingPushPreferences, isFalse);
    expect(app.registration?.pushPreferences?.enabled, isTrue);
  });

  test(
    'a revoked key while saving push preferences returns to setup',
    () async {
      final app = controller();
      await app.connect(serverUrl, clientKey);
      backend.acceptedKey = null;

      await app.setPushPreferences(const PushPreferences(enabled: false));

      expect(app.phase, ConnectionPhase.disconnected);
      expect(store.saved, isNull);
    },
  );

  test('the inbox producers are the distinct producers, by name', () async {
    backend
      ..publish('e-1', 'Disk full', producer: {'id': 'p-2', 'name': 'nas'})
      ..publish('e-2', 'Build failed')
      ..publish('e-3', 'Disk fine', producer: {'id': 'p-2', 'name': 'nas'});
    final app = controller();
    await app.connect(serverUrl, clientKey);

    expect(
      [for (final p in app.inboxProducers) (p.id, p.name)],
      [('p-2', 'nas'), ('p-1', 'nightly-build')],
    );
  });
}
