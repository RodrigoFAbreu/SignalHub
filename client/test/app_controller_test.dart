import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/api/signalhub_api.dart';
import 'package:signalhub_client/src/app_controller.dart';
import 'package:signalhub_client/src/connection/pairing_uri.dart';
import 'package:signalhub_client/src/connection/server_credentials.dart';
import 'package:signalhub_client/src/models/client_registration.dart';
import 'package:signalhub_client/src/models/event.dart';
import 'package:signalhub_client/src/models/inbox_filter.dart';
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
    redeemPairing: backend.redeemPairing,
    push: withPush ? push : null,
  );

  /// A build without its own push options, which takes them from the server.
  AppController servedPushController(FakeServedPushStarter starter) =>
      AppController(
        store: store,
        apiFactory: (credentials) =>
            backend.api(credentials.baseUrl, credentials.clientKey),
        redeemPairing: backend.redeemPairing,
        startServedPush: starter.call,
      );

  int pushConfigReads() => backend.requests
      .where((r) => r.url.path == '/api/v1/client/push-config')
      .length;

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

  group('pairing', () {
    setUp(() {
      backend
        ..acceptedKey = null
        ..pairingCodes.add(pairingCode)
        ..publish('e-1', 'Build failed');
    });

    test('registers this device and connects with its own key', () async {
      final app = controller();

      final error = await app.pair(pairingUri);

      expect(error, isNull);
      expect(app.phase, ConnectionPhase.connected);
      expect(store.saved?.baseUrl, serverUrl);
      expect(store.saved?.clientKey, pairedClientKey);
      expect(app.registration?.name, 'Pixel 8');
      expect(app.events.single.title, 'Build failed');
      expect(app.pushStatus, PushStatus.registered);
      expect(backend.pushToken, 'device-token-1');
      // The redemption answers the registration: it is not read again.
      expect(
        backend.requests.where((r) => r.url.path == '/api/v1/client'),
        isEmpty,
      );
    });

    test('a used code says so and saves nothing', () async {
      // Another device redeemed it first.
      await backend.redeemPairing(serverUrl, pairingCode);
      final app = controller();

      final error = await app.pair(pairingUri);

      expect(error, const PairingRejectedException().message);
      expect(app.phase, isNot(ConnectionPhase.connected));
      expect(store.saved, isNull);
    });

    test('an unreachable server is named', () async {
      backend.offline = true;
      final app = controller();

      final error = await app.pair(pairingUri);

      expect(error, 'Could not reach the server ($serverUrl)');
      expect(store.saved, isNull);
      // The code was not used: pairing works once the server is reachable.
      backend.offline = false;
      expect(await app.pair(pairingUri), isNull);
    });

    test('anything but a pairing link is reported without a request', () async {
      final app = controller();

      final error = await app.pair(clientKey);

      expect(error, PairingUri.invalid);
      expect(backend.requests, isEmpty);
    });

    test('a device paired and then revoked returns to setup', () async {
      final app = controller();
      await app.pair(pairingUri);
      backend.acceptedKey = null;

      await app.refresh();

      expect(app.phase, ConnectionPhase.disconnected);
      expect(store.saved, isNull);
    });
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
    expect(app.serverUnreachable, isTrue);
    // Push registration waits for the server rather than failing too.
    expect(app.pushStatus, PushStatus.pending);

    backend.offline = false;
    await app.refresh();
    expect(app.error, isNull);
    expect(app.serverUnreachable, isFalse);
    expect(app.pushStatus, PushStatus.registered);
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

  group('push options served by the server', () {
    late FakeServedPushStarter starter;

    setUp(() {
      starter = FakeServedPushStarter();
      backend.pushConfig = servedPushConfig;
    });

    test('a build without its own sets push up with them', () async {
      final app = servedPushController(starter);
      expect(app.pushStatus, PushStatus.pending);

      await app.connect(serverUrl, clientKey);

      final started = starter.started.single;
      expect(started.provider, 'fcm');
      expect(started.options['FIREBASE_ANDROID_APP_ID'], '1:1234:android:ab');
      expect(app.pushStatus, PushStatus.registered);
      expect(backend.pushTarget?['provider'], 'fake');
      expect(backend.pushToken, 'device-token-1');
    });

    test('they are read with the client key', () async {
      await servedPushController(starter).connect(serverUrl, clientKey);

      final read = backend.requests.singleWhere(
        (r) => r.url.path == '/api/v1/client/push-config',
      );
      expect(read.headers['Authorization'], 'Bearer $clientKey');
    });

    test('the build\'s own options take precedence', () async {
      final app = AppController(
        store: store,
        apiFactory: (credentials) =>
            backend.api(credentials.baseUrl, credentials.clientKey),
        redeemPairing: backend.redeemPairing,
        push: push,
        startServedPush: starter.call,
      );

      await app.connect(serverUrl, clientKey);

      expect(pushConfigReads(), 0);
      expect(starter.started, isEmpty);
      expect(app.pushStatus, PushStatus.registered);
      expect(backend.pushToken, 'device-token-1');
    });

    test('a server serving none leaves push off and says so', () async {
      backend.pushConfig = null;
      final app = servedPushController(starter);

      await app.connect(serverUrl, clientKey);

      expect(app.phase, ConnectionPhase.connected);
      expect(app.pushStatus, PushStatus.notConfigured);
      expect(starter.started, isEmpty);
      expect(backend.pushTarget, isNull);
    });

    test('options that do not work leave push off until fixed', () async {
      starter.accepts = false;
      final app = servedPushController(starter);

      await app.connect(serverUrl, clientKey);

      expect(app.pushStatus, PushStatus.unsupported);
      expect(backend.pushTarget, isNull);

      // The operator fixes them; the next refresh tries again.
      starter.accepts = true;
      await app.refresh();

      expect(starter.started, hasLength(2));
      expect(app.pushStatus, PushStatus.registered);
    });

    test('options the app cannot read are not started', () async {
      backend.pushConfig = {
        'provider': 'fcm',
        'options': {'FIREBASE_PROJECT_ID': 7},
      };
      final app = servedPushController(starter);

      await app.connect(serverUrl, clientKey);

      expect(app.pushStatus, PushStatus.failed);
      expect(starter.started, isEmpty);
    });

    test('an unreachable server is retried on the next refresh', () async {
      store.saved = ServerCredentials.parse(serverUrl, clientKey);
      backend.offline = true;
      final app = servedPushController(starter);

      await app.start();

      // Nothing to try until the server answers.
      expect(app.pushStatus, PushStatus.pending);
      expect(starter.started, isEmpty);
      backend.offline = false;
      await app.refresh();

      expect(app.pushStatus, PushStatus.registered);
    });

    test('push starts once, however often the app refreshes', () async {
      final app = servedPushController(starter);
      await app.connect(serverUrl, clientKey);

      await Future.wait([app.refresh(), app.refresh()]);

      expect(starter.started, hasLength(1));
      expect(app.pushStatus, PushStatus.registered);
      expect(pushConfigReads(), 3);
    });

    test('concurrent refreshes start push once', () async {
      store.saved = ServerCredentials.parse(serverUrl, clientKey);
      final app = servedPushController(starter);

      await Future.wait([app.start(), app.refresh()]);

      expect(starter.started, hasLength(1));
      expect(app.pushStatus, PushStatus.registered);
    });

    test('pushes of the started service reach the inbox', () async {
      final app = servedPushController(starter);
      await app.connect(serverUrl, clientKey);
      backend.publish('e-1', 'Build failed');

      starter.push.received.add(
        const PushNotice(title: 'Build failed', eventId: 'e-1', opened: true),
      );
      await pumpEventQueue();

      expect(app.takeEventToOpen(), 'e-1');
      expect(app.events.single.title, 'Build failed');
    });

    test('other options need a restart and register nothing', () async {
      final app = servedPushController(starter);
      await app.connect(serverUrl, clientKey);
      await app.disconnect();
      expect(starter.push.tokenDeleted, isTrue);
      starter.push.token = 'device-token-2';
      // Another server, with its own Firebase project.
      backend.pushConfig = {
        'provider': 'fcm',
        'options': {
          ...servedPushConfig['options']! as Map<String, Object?>,
          'FIREBASE_PROJECT_ID': 'other-project',
        },
      };

      await app.connect(serverUrl, clientKey);

      expect(app.pushStatus, PushStatus.restartRequired);
      expect(starter.started, hasLength(1));
      expect(backend.pushTarget, isNull);
    });

    test('the same options after reconnecting register again', () async {
      final app = servedPushController(starter);
      await app.connect(serverUrl, clientKey);
      await app.disconnect();
      starter.push.token = 'device-token-2';

      await app.connect(serverUrl, clientKey);

      expect(starter.started, hasLength(1));
      expect(app.pushStatus, PushStatus.registered);
      expect(backend.pushToken, 'device-token-2');
    });

    test(
      'a key revoked before the options are read returns to setup',
      () async {
        final app = servedPushController(starter);
        await app.connect(serverUrl, clientKey);
        backend.acceptedKey = null;

        await app.refresh();

        expect(app.phase, ConnectionPhase.disconnected);
        expect(app.pushStatus, PushStatus.pending);
      },
    );
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

  group('inbox filters', () {
    const unreadOnly = InboxFilter(unreadOnly: true);

    Map<String, List<String>> lastListing() => backend.requests
        .lastWhere((r) => r.url.path == '/api/v1/events')
        .url
        .queryParametersAll;

    test('start with every event', () async {
      final app = controller();
      await app.connect(serverUrl, clientKey);

      expect(app.filter, InboxFilter.none);
      expect(app.filter.isActive, isFalse);
      expect(lastListing().keys, ['limit']);
    });

    test('are applied by the server, from the newest page', () async {
      backend
        ..publish('e-1', 'Disk full', producer: {'id': 'p-2', 'name': 'nas'})
        ..publish('e-2', 'Build failed')
        ..publish('e-3', 'Build fixed', category: 'COMPLETED');
      final app = controller();
      await app.connect(serverUrl, clientKey);

      await app.setFilter(
        const InboxFilter(
          producerIds: {'p-1'},
          categories: {EventCategory.blocked},
        ),
      );

      expect(lastListing(), {
        'limit': ['${AppController.pageSize}'],
        'producerId': ['p-1'],
        'category': ['BLOCKED'],
      });
      expect(app.events.map((e) => e.id), ['e-2']);
      expect(app.inboxLoaded, isTrue);
      // The unread count stays the server's, for every event.
      expect(app.unreadCount, 3);
    });

    test('keep paging and refreshing with the filter', () async {
      for (var i = 1; i <= AppController.pageSize * 2; i++) {
        backend.publish(
          'e-$i',
          'Event $i',
          severity: i.isEven ? 'CRITICAL' : 'LOW',
        );
      }
      final app = controller();
      await app.connect(serverUrl, clientKey);
      const critical = InboxFilter(severities: {EventSeverity.critical});
      await app.setFilter(critical);

      expect(app.events, hasLength(AppController.pageSize));
      expect(app.hasMore, isFalse);
      expect(
        app.events.every((e) => e.severity == EventSeverity.critical),
        isTrue,
      );

      backend.publish('e-new', 'New and critical', severity: 'CRITICAL');
      await app.refresh();

      expect(app.filter, critical);
      expect(app.events.first.id, 'e-new');
      expect(lastListing()['severity'], ['CRITICAL']);
    });

    test('pass the filter with the cursor for older pages', () async {
      for (var i = 1; i <= AppController.pageSize + 3; i++) {
        backend.publish('e-$i', 'Event $i');
      }
      final app = controller();
      await app.connect(serverUrl, clientKey);
      await app.setFilter(unreadOnly);

      await app.loadMore();

      expect(lastListing()['read'], ['false']);
      expect(lastListing()['cursor'], isNotNull);
      expect(app.events, hasLength(AppController.pageSize + 3));
    });

    test('an unread-only view lists unread events only', () async {
      backend
        ..publish('e-1', 'Seen', readAt: '2026-09-25T12:10:00Z')
        ..publish('e-2', 'Not seen');
      final app = controller();
      await app.connect(serverUrl, clientKey);

      await app.setFilter(unreadOnly);

      expect(app.events.map((e) => e.id), ['e-2']);
    });

    test('an older server\'s read events are left out of the unread-only '
        'view', () async {
      backend.readFilter = false;
      for (var i = 1; i <= AppController.pageSize + 2; i++) {
        backend.publish(
          'e-$i',
          'Event $i',
          readAt: i > 2 ? '2026-09-25T12:10:00Z' : null,
        );
      }
      final app = controller();
      await app.connect(serverUrl, clientKey);

      await app.setFilter(unreadOnly);

      // The first page held only read events; the next one has the rest.
      expect(app.events, isEmpty);
      expect(app.hasMore, isTrue);
      await app.loadMore();
      expect(app.events.map((e) => e.id), ['e-2', 'e-1']);
    });

    test(
      'an event read while shown stays until the inbox is read again',
      () async {
        backend.publish('e-1', 'Build failed');
        final app = controller();
        await app.connect(serverUrl, clientKey);
        await app.setFilter(unreadOnly);

        await app.markRead('e-1');

        expect(app.events.single.isRead, isTrue);
        await app.refresh();
        expect(app.events, isEmpty);
      },
    );

    test('are cleared with one action', () async {
      backend
        ..publish('e-1', 'Seen', readAt: '2026-09-25T12:10:00Z')
        ..publish('e-2', 'Not seen', category: 'INFO');
      final app = controller();
      await app.connect(serverUrl, clientKey);
      await app.setFilter(
        const InboxFilter(unreadOnly: true, categories: {EventCategory.info}),
      );

      await app.clearFilter();

      expect(app.filter, InboxFilter.none);
      expect(app.events.map((e) => e.id), ['e-2', 'e-1']);
      expect(lastListing().keys, ['limit']);
    });

    test('a page read with the previous filter is not shown', () async {
      for (var i = 1; i <= AppController.pageSize + 1; i++) {
        backend.publish('e-$i', 'Event $i');
      }
      final app = controller();
      await app.connect(serverUrl, clientKey);

      backend.holdOlderPages = Completer();
      final older = app.loadMore();
      await app.setFilter(const InboxFilter(categories: {EventCategory.info}));
      backend.holdOlderPages!.complete();
      await older;

      expect(app.events, isEmpty);
      expect(app.loadingMore, isFalse);
    });

    test('keep the producers to choose from that they hide', () async {
      backend
        ..publish('e-1', 'Disk full', producer: {'id': 'p-2', 'name': 'nas'})
        ..publish('e-2', 'Build failed');
      final app = controller();
      await app.connect(serverUrl, clientKey);

      await app.setFilter(const InboxFilter(producerIds: {'p-2'}));

      expect(app.events.map((e) => e.id), ['e-1']);
      expect(
        [for (final p in app.inboxProducers) p.name],
        ['nas', 'nightly-build'],
      );
    });

    test(
      'allow marking all read only while they hide no event by what it is',
      () async {
        backend
          ..publish('e-1', 'Disk full', producer: {'id': 'p-2', 'name': 'nas'})
          ..publish('e-2', 'Build failed');
        final app = controller();
        await app.connect(serverUrl, clientKey);

        await app.setFilter(const InboxFilter(producerIds: {'p-2'}));
        expect(app.canMarkAllRead, isFalse);
        expect(await app.markAllRead(), isNull);
        expect(backend.isRead('e-1'), isFalse);
        expect(backend.isRead('e-2'), isFalse);

        await app.setFilter(unreadOnly);
        expect(app.canMarkAllRead, isTrue);
        expect(await app.markAllRead(), isNull);
        expect(backend.isRead('e-1'), isTrue);
        expect(backend.isRead('e-2'), isTrue);
      },
    );

    test('are forgotten with the server', () async {
      backend.publish('e-1', 'Build failed');
      final app = controller();
      await app.connect(serverUrl, clientKey);
      await app.setFilter(unreadOnly);

      await app.disconnect();

      expect(app.filter, InboxFilter.none);
      expect(app.inboxProducers, isEmpty);
    });
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

  test('an event\'s link reaches the inbox and its screen', () async {
    backend
      ..publish('e-1', 'Without a link')
      ..publish('e-2', 'Build failed', link: 'https://ci.example.com/runs/1');
    final app = controller();
    await app.connect(serverUrl, clientKey);

    expect(app.events.map((e) => e.link), [
      Uri.parse('https://ci.example.com/runs/1'),
      null,
    ]);

    backend.publish('e-3', 'Deployed', link: 'https://deploy.example.com/42');
    expect(
      (await app.event('e-3')).link,
      Uri.parse('https://deploy.example.com/42'),
    );
    // Marking read answers with the server's event, link included.
    expect(
      (await app.markRead('e-2')).event?.link,
      Uri.parse('https://ci.example.com/runs/1'),
    );
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

    final unread = await app.setRead('e-1', read: false);

    expect(unread.error, isNull);
    expect(unread.event?.isRead, isFalse);
    expect(backend.isRead('e-1'), isFalse);
    expect(app.events.single.isRead, isFalse);
    expect(app.unreadCount, 1);

    backend.offline = true;
    final failed = await app.setRead('e-1', read: false);
    expect(failed.error, 'Could not reach the server');
    expect(failed.event, isNull);
  });

  test('marks an event read again from its screen', () async {
    backend.publish('e-1', 'Build failed');
    final app = controller();
    await app.connect(serverUrl, clientKey);

    final read = await app.setRead('e-1', read: true);

    expect(read.error, isNull);
    expect(read.event?.isRead, isTrue);
    expect(app.events.single.isRead, isTrue);
    expect(app.unreadCount, 0);

    backend.offline = true;
    final failed = await app.setRead('e-1', read: false);
    expect(failed.error, 'Could not reach the server');
    expect(app.events.single.isRead, isTrue);
    expect(app.unreadCount, 0);
  });

  test('marking read on opening returns the server\'s event', () async {
    backend.publish('e-1', 'Build failed');
    final app = controller();
    await app.connect(serverUrl, clientKey);

    expect((await app.markRead('e-1')).event?.readAt, isNotNull);
    // Already read: the inbox's event, without a request.
    backend.offline = true;
    expect((await app.markRead('e-1')).event?.isRead, isTrue);

    backend.publish('e-2', 'Not in the inbox');
    final failed = await app.markRead('e-2');
    expect(failed.event, isNull);
    expect(failed.error, 'Could not reach the server');
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

  group('device management', () {
    const tablet = 'c-tablet';
    const laptop = 'c-laptop';

    setUp(() {
      backend
        ..admin = true
        ..addClient(tablet, 'Tablet')
        ..addClient(laptop, 'Laptop', admin: true);
    });

    int deviceRequests() => backend.requests
        .where((r) => r.url.path.startsWith('/api/v1/client/devices'))
        .length;

    test('an admin device lists every device, active ones first', () async {
      backend.otherClients.first['revokedAt'] = '2026-09-26T09:00:00Z';
      backend.addClient('c-phone', 'Old phone');
      final app = controller();
      await app.connect(serverUrl, clientKey);
      expect(app.registration?.admin, isTrue);
      expect(app.canManageDevices, isTrue);

      await app.loadDevices();

      expect(
        [for (final d in app.devices!) (d.name, d.admin, d.isRevoked)],
        [
          ('Pixel 8', true, false),
          ('Laptop', true, false),
          ('Old phone', false, false),
          ('Tablet', false, true),
        ],
      );
      expect(app.devicesError, isNull);
      expect(app.lostAdminRights, isFalse);
    });

    test('a device that is not an admin reads no devices', () async {
      backend.admin = false;
      final app = controller();
      await app.connect(serverUrl, clientKey);

      await app.loadDevices();

      expect(app.canManageDevices, isFalse);
      expect(app.devices, isNull);
      expect(app.lostAdminRights, isFalse);
      expect(deviceRequests(), 0);
    });

    test('a server without admin devices offers nothing', () async {
      backend.admin = null;
      final app = controller();
      await app.connect(serverUrl, clientKey);

      await app.loadDevices();

      expect(app.registration?.admin, isFalse);
      expect(app.canManageDevices, isFalse);
      expect(deviceRequests(), 0);
    });

    test('a server without the device endpoints offers nothing', () async {
      backend.deviceEndpoints = false;
      final app = controller();
      await app.connect(serverUrl, clientKey);

      await app.loadDevices();

      expect(app.canManageDevices, isFalse);
      expect(app.devices, isNull);
      expect(app.devicesError, isNull);
      expect(app.lostAdminRights, isFalse);
    });

    test('makes a device an admin', () async {
      final app = controller();
      await app.connect(serverUrl, clientKey);
      await app.loadDevices();

      final error = await app.makeDeviceAdmin(tablet);

      expect(error, isNull);
      expect(backend.otherClients.first['admin'], isTrue);
      expect(app.devices!.firstWhere((d) => d.id == tablet).admin, isTrue);
      expect(app.changingDeviceId, isNull);
    });

    test('revokes a device, which moves after the active ones', () async {
      final app = controller();
      await app.connect(serverUrl, clientKey);
      await app.loadDevices();

      final error = await app.revokeDevice(tablet);

      expect(error, isNull);
      expect(backend.otherClients.first['revokedAt'], isNotNull);
      expect(app.devices!.last.id, tablet);
      expect(app.devices!.last.isRevoked, isTrue);
    });

    test('a refused change says why and shows the device as it is', () async {
      final app = controller();
      await app.connect(serverUrl, clientKey);
      await app.loadDevices();
      // Another admin device made it an admin meanwhile.
      backend.otherClients.first['admin'] = true;

      final error = await app.revokeDevice(tablet);

      expect(error, 'The server answered 409: Client is an admin device');
      expect(backend.otherClients.first['revokedAt'], isNull);
      expect(app.devices!.firstWhere((d) => d.id == tablet).admin, isTrue);
    });

    test('a failed change is reported and changes nothing', () async {
      final app = controller();
      await app.connect(serverUrl, clientKey);
      await app.loadDevices();
      backend.offline = true;

      final error = await app.revokeDevice(tablet);

      expect(error, 'Could not reach the server');
      expect(app.devices!.firstWhere((d) => d.id == tablet).isRevoked, false);
      expect(app.changingDeviceId, isNull);
    });

    test('rights taken away meanwhile are reported on reading', () async {
      final app = controller();
      await app.connect(serverUrl, clientKey);
      backend.admin = false;

      await app.loadDevices();

      expect(app.lostAdminRights, isTrue);
      expect(app.devices, isNull);
      // The registration was re-read, so nothing is offered any more.
      expect(app.registration?.admin, isFalse);
      expect(app.canManageDevices, isFalse);
    });

    test('rights taken away meanwhile are reported on a change', () async {
      final app = controller();
      await app.connect(serverUrl, clientKey);
      await app.loadDevices();
      backend.admin = false;

      final error = await app.makeDeviceAdmin(tablet);

      expect(error, AppController.notAdminMessage);
      expect(backend.otherClients.first['admin'], isFalse);
      expect(app.lostAdminRights, isTrue);
      expect(app.devices, isNull);
      expect(app.canManageDevices, isFalse);
    });

    test('rights taken away, seen in a refresh, are reported', () async {
      final app = controller();
      await app.connect(serverUrl, clientKey);
      await app.loadDevices();
      backend.admin = false;

      await app.refresh();
      await app.loadDevices();

      expect(app.lostAdminRights, isTrue);
      expect(app.devices, isNull);

      // Once said, it is not said again.
      await app.loadDevices();
      expect(app.lostAdminRights, isFalse);
    });

    test('a failed listing is reported and can be retried', () async {
      final app = controller();
      await app.connect(serverUrl, clientKey);
      backend.offline = true;

      await app.loadDevices();
      expect(app.devicesError, 'Could not reach the server');
      expect(app.devices, isNull);

      backend.offline = false;
      await app.loadDevices();
      expect(app.devicesError, isNull);
      expect(app.devices, hasLength(3));
    });

    group('deleting', () {
      const oldPhone = 'c-old-phone';

      setUp(() => backend.addClient(oldPhone, 'Old phone', revoked: true));

      Future<AppController> withDevices() async {
        final app = controller();
        await app.connect(serverUrl, clientKey);
        await app.loadDevices();
        return app;
      }

      List<String> listed(AppController app) => [
        for (final d in app.devices!) d.id,
      ];

      test('deletes a revoked device, which leaves the list', () async {
        final app = await withDevices();
        expect(app.canDeleteDevices, isTrue);

        final error = await app.deleteDevice(oldPhone);

        expect(error, isNull);
        expect(
          backend.otherClients.map((c) => c['id']),
          isNot(contains(oldPhone)),
        );
        expect(listed(app), isNot(contains(oldPhone)));
        expect(app.changingDeviceId, isNull);
      });

      test('a device deleted meanwhile leaves the list', () async {
        final app = await withDevices();
        // The operator deleted it on the admin page.
        backend.otherClients.removeWhere((c) => c['id'] == oldPhone);

        final error = await app.deleteDevice(oldPhone);

        expect(error, isNull);
        expect(listed(app), isNot(contains(oldPhone)));
        expect(app.canDeleteDevices, isTrue);
      });

      test('an active device is refused and shown as it is', () async {
        final app = await withDevices();
        // The app offers no delete on an active device; the server refuses
        // one anyway.
        final error = await app.deleteDevice(tablet);

        expect(error, 'The server answered 409: Client is not revoked');
        expect(backend.otherClients.map((c) => c['id']), contains(tablet));
        expect(listed(app), contains(tablet));
        expect(app.canDeleteDevices, isTrue);
      });

      for (final status in [404, 405]) {
        test(
          'a server older than deleting ($status) stops offering it',
          () async {
            backend.noDeviceDeletion = status;
            final app = await withDevices();

            final error = await app.deleteDevice(oldPhone);

            expect(error, AppController.deletingUnsupportedMessage);
            expect(listed(app), contains(oldPhone));
            expect(app.canDeleteDevices, isFalse);
            // Managing devices otherwise goes on.
            expect(app.canManageDevices, isTrue);
            expect(await app.revokeDevice(tablet), isNull);
          },
        );
      }

      test('rights taken away meanwhile are reported', () async {
        final app = await withDevices();
        backend.admin = false;

        final error = await app.deleteDevice(oldPhone);

        expect(error, AppController.notAdminMessage);
        expect(backend.otherClients.map((c) => c['id']), contains(oldPhone));
        expect(app.lostAdminRights, isTrue);
        expect(app.devices, isNull);
        expect(app.canDeleteDevices, isFalse);
      });

      test('a failed delete is reported and changes nothing', () async {
        final app = await withDevices();
        backend.offline = true;

        final error = await app.deleteDevice(oldPhone);

        expect(error, 'Could not reach the server');
        expect(listed(app), contains(oldPhone));
        expect(app.canDeleteDevices, isTrue);
      });

      test('a revoked key while deleting returns to setup', () async {
        final app = await withDevices();
        backend.acceptedKey = null;

        final error = await app.deleteDevice(oldPhone);

        expect(error, isNull);
        expect(app.phase, ConnectionPhase.disconnected);
        expect(app.devices, isNull);
      });
    });

    test('a revoked key while managing devices returns to setup', () async {
      final app = controller();
      await app.connect(serverUrl, clientKey);
      await app.loadDevices();
      backend.acceptedKey = null;

      final error = await app.revokeDevice(tablet);

      expect(error, isNull);
      expect(app.phase, ConnectionPhase.disconnected);
      expect(app.devices, isNull);
      expect(store.saved, isNull);
    });
  });

  group('pairing from an admin device', () {
    setUp(() => backend.admin = true);

    test('creates a code whose link is the server\'s pairing URI', () async {
      final app = controller();
      await app.connect(serverUrl, clientKey);
      expect(app.canCreatePairings, isTrue);

      final error = await app.createPairing('Tablet');

      expect(error, isNull);
      expect(backend.devicePairingNames, ['Tablet']);
      expect(app.pairing?.name, 'Tablet');
      expect(app.pairingLink, app.pairing?.uri);
      expect(app.creatingPairing, isFalse);
      final link = PairingUri.parse(app.pairingLink!);
      expect(link.serverUrl, serverUrl);
      expect(link.code, app.pairing?.code);

      app.clearPairing();
      expect(app.pairing, isNull);
      expect(app.pairingLink, isNull);
    });

    test('without a public address, the link names this server', () async {
      backend.publicUrl = null;
      final app = controller();
      await app.connect('$serverUrl/', clientKey);

      await app.createPairing('Tablet');

      expect(app.pairing?.uri, isNull);
      final link = PairingUri.parse(app.pairingLink!);
      expect(link.serverUrl, serverUrl);
      expect(link.code, app.pairing?.code);
    });

    test('a device that is not an admin cannot create codes', () async {
      backend.admin = false;
      final app = controller();
      await app.connect(serverUrl, clientKey);

      expect(app.canCreatePairings, isFalse);
    });

    test('rights taken away meanwhile are reported', () async {
      final app = controller();
      await app.connect(serverUrl, clientKey);
      backend.admin = false;

      final error = await app.createPairing('Tablet');

      expect(error, AppController.notAdminMessage);
      expect(app.pairing, isNull);
      expect(app.lostAdminRights, isTrue);
      expect(app.canCreatePairings, isFalse);
      expect(backend.devicePairingNames, isEmpty);
    });

    test('a server released before them stops offering them', () async {
      backend.devicePairings = false;
      final app = controller();
      await app.connect(serverUrl, clientKey);

      final error = await app.createPairing('Tablet');

      expect(error, AppController.pairingUnsupportedMessage);
      expect(app.pairing, isNull);
      expect(app.canCreatePairings, isFalse);
      // Device management itself still works there.
      expect(app.canManageDevices, isTrue);
    });

    test('a failed request is reported and can be retried', () async {
      final app = controller();
      await app.connect(serverUrl, clientKey);
      backend.offline = true;

      expect(await app.createPairing('Tablet'), 'Could not reach the server');
      expect(app.pairing, isNull);
      expect(app.canCreatePairings, isTrue);

      backend.offline = false;
      expect(await app.createPairing('Tablet'), isNull);
      expect(app.pairing, isNotNull);
    });

    test('a revoked key returns to setup and forgets the code', () async {
      final app = controller();
      await app.connect(serverUrl, clientKey);
      await app.createPairing('Tablet');
      backend.acceptedKey = null;

      final error = await app.createPairing('Laptop');

      expect(error, isNull);
      expect(app.phase, ConnectionPhase.disconnected);
      expect(app.pairing, isNull);
    });
  });

  group('whether a pairing code was used', () {
    setUp(() => backend.admin = true);

    const unchanged = (connected: null, error: null);

    Future<AppController> showingCode() async {
      final app = controller();
      await app.connect(serverUrl, clientKey);
      await app.createPairing('Tablet');
      return app;
    }

    test('a code not used yet stays shown', () async {
      final app = await showingCode();
      final shown = app.pairing;

      expect(await app.checkPairing(), unchanged);

      expect(app.pairing, same(shown));
      expect(backend.pairingStatusRequests, 1);
    });

    test('a used code names the device and is forgotten', () async {
      final app = await showingCode();
      await app.loadDevices();
      backend.usePairing('Tablet of Anna');

      final result = await app.checkPairing();

      expect(result, (connected: 'Tablet of Anna', error: null));
      expect(app.pairing, isNull);
      expect(app.canCreatePairings, isTrue);
      // The device list shows it once read again.
      await app.loadDevices();
      expect(app.devices?.map((d) => d.name), contains('Tablet of Anna'));
      // Nothing is asked once no code is shown.
      await app.checkPairing();
      expect(backend.pairingStatusRequests, 1);
    });

    test('an answer about a code dismissed meanwhile is ignored', () async {
      final app = await showingCode();
      backend.usePairing('Tablet');
      final asking = app.checkPairing();
      app.clearPairing();
      await app.createPairing('Laptop');
      final laptop = app.pairing;

      expect(await asking, unchanged);
      expect(app.pairing, same(laptop));
    });

    test('rights taken away meanwhile are reported and end the code', () async {
      final app = await showingCode();
      backend.admin = false;

      final result = await app.checkPairing();

      expect(result, (connected: null, error: AppController.notAdminMessage));
      expect(app.pairing, isNull);
      expect(app.lostAdminRights, isTrue);
      expect(app.canCreatePairings, isFalse);
    });

    test('a revoked key returns to setup', () async {
      final app = await showingCode();
      backend.acceptedKey = null;

      expect(await app.checkPairing(), unchanged);

      expect(app.phase, ConnectionPhase.disconnected);
      expect(app.pairing, isNull);
    });

    test('a failed request keeps the code and asks again', () async {
      final app = await showingCode();
      backend.offline = true;

      expect(await app.checkPairing(), unchanged);
      expect(app.pairing, isNotNull);

      backend.offline = false;
      backend.usePairing('Tablet');
      expect((await app.checkPairing()).connected, 'Tablet');
    });

    test('a server whose codes have no ID is never asked', () async {
      backend.pairingIds = false;
      final app = await showingCode();

      expect(await app.checkPairing(), unchanged);

      expect(app.pairing, isNotNull);
      expect(backend.pairingStatusRequests, 0);
    });

    for (final status in [404, 405]) {
      test('a server answering $status is asked once per code', () async {
        backend.noPairingStatus = status;
        final app = await showingCode();

        expect(await app.checkPairing(), unchanged);
        expect(await app.checkPairing(), unchanged);

        expect(app.pairing, isNotNull);
        expect(app.lostAdminRights, isFalse);
        expect(backend.pairingStatusRequests, 1);
      });
    }
  });
}
