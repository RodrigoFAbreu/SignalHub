import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/app_controller.dart';
import 'package:signalhub_client/src/connection/server_credentials.dart';
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
}
