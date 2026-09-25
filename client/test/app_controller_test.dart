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
    expect(app.latestEvent?.title, 'Build failed');
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

  test('pushes are listed once per event, newest first', () async {
    final app = controller();
    await app.connect(serverUrl, clientKey);
    backend.publish('e-1', 'First');

    push.received
      ..add(const PushNotice(title: 'First', eventId: 'e-1'))
      // At-least-once delivery: the same event again.
      ..add(const PushNotice(title: 'First', eventId: 'e-1'))
      ..add(const PushNotice(title: 'Second', eventId: 'e-2'));
    await pumpEventQueue();

    expect(app.notices.map((n) => n.title), ['Second', 'First']);
    // A push is a signal to look: the app re-reads the newest event.
    expect(app.latestEvent?.title, 'First');
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
