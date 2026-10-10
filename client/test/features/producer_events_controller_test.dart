import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/app_controller.dart';
import 'package:signalhub_client/src/connection/server_credentials.dart';
import 'package:signalhub_client/src/features/producer_events_controller.dart';
import 'package:signalhub_client/src/models/event.dart';
import 'package:signalhub_client/src/models/inbox_filter.dart';

import '../support/fakes.dart';

void main() {
  const ci = {'id': 'p-ci', 'name': 'ci-pipeline'};
  const backup = {'id': 'p-backup', 'name': 'backup-jobs'};

  late FakeBackend backend;
  late AppController app;
  late ProducerEventsController events;

  setUp(() async {
    backend = FakeBackend();
    final store = InMemoryCredentialsStore()
      ..saved = ServerCredentials.parse(serverUrl, clientKey);
    app = AppController(
      store: store,
      apiFactory: (credentials) =>
          backend.api(credentials.baseUrl, credentials.clientKey),
      redeemPairing: backend.redeemPairing,
      push: FakePushService(),
    );
  });

  tearDown(() {
    events.dispose();
    app.dispose();
  });

  Future<void> start({int pageSize = 30}) async {
    await app.start();
    events = ProducerEventsController(
      gateway: app,
      producerId: 'p-ci',
      pageSize: pageSize,
    );
    await events.load();
  }

  Iterable<Uri> listings() => backend.requests
      .where((r) => r.url.path == '/api/v1/events' && r.method == 'GET')
      .map((r) => r.url);

  test('lists only the producer\'s events, newest first', () async {
    backend
      ..publish('e1', 'Backup done', producer: backup)
      ..publish('e2', 'Build passed', producer: ci)
      ..publish('e3', 'Disk full', producer: backup)
      ..publish('e4', 'Deploy done', producer: ci);

    await start();

    expect(events.events.map((e) => e.id), ['e4', 'e2']);
    expect(events.loaded, isTrue);
    expect(listings().last.queryParametersAll['producerId'], ['p-ci']);
  });

  test('has its own filters, which the Inbox tab does not see', () async {
    backend
      ..publish('e1', 'Read one', producer: ci, readAt: '2026-09-25T12:10:00Z')
      ..publish('e2', 'Unread one', producer: ci);
    await start();

    await events.setExtras(const InboxFilter(unreadOnly: true));

    expect(events.events.map((e) => e.id), ['e2']);
    expect(events.filter.producerIds, {'p-ci'});
    expect(events.narrowed, isTrue);
    expect(app.filter, InboxFilter.none);
    expect(listings().last.queryParametersAll['read'], ['false']);
    expect(listings().last.queryParametersAll['producerId'], ['p-ci']);
  });

  test('categories and severities combine with the producer', () async {
    backend
      ..publish('e1', 'Info', producer: ci, category: 'INFO', severity: 'LOW')
      ..publish('e2', 'Blocked', producer: ci)
      ..publish('e3', 'Blocked elsewhere', producer: backup);
    await start();

    await events.setExtras(
      const InboxFilter(categories: {EventCategory.blocked}),
    );

    expect(events.events.map((e) => e.id), ['e2']);
    // A producer in the extras is not the screen's to change.
    await events.setExtras(InboxFilter(producerIds: {'p-backup'}));
    expect(events.filter.producerIds, {'p-ci'});
  });

  test('reads older pages as they are needed', () async {
    for (var i = 1; i <= 5; i++) {
      backend.publish('e$i', 'Event $i', producer: ci);
    }
    await start(pageSize: 2);

    expect(events.events.map((e) => e.id), ['e5', 'e4']);
    expect(events.hasMore, isTrue);

    await events.loadMore();
    await events.loadMore();

    expect(events.events.map((e) => e.id), ['e5', 'e4', 'e3', 'e2', 'e1']);
    expect(events.hasMore, isFalse);
  });

  test('a page that fails to load says so and can be tried again', () async {
    for (var i = 1; i <= 3; i++) {
      backend.publish('e$i', 'Event $i', producer: ci);
    }
    await start(pageSize: 2);
    backend.offline = true;

    await events.loadMore();

    expect(events.loadMoreError, isNotNull);
    expect(events.events, hasLength(2));
    backend.offline = false;
    await events.loadMore();
    expect(events.loadMoreError, isNull);
    expect(events.events, hasLength(3));
  });

  test('a first page that fails says so, and the list loads later', () async {
    backend.publish('e1', 'Event', producer: ci);
    backend.offline = true;
    await app.start();
    events = ProducerEventsController(gateway: app, producerId: 'p-ci');

    await events.load();

    expect(events.loaded, isFalse);
    expect(events.error?.statusCode, isNull);
    backend.offline = false;
    await events.load();
    expect(events.loaded, isTrue);
    expect(events.error, isNull);
    expect(events.events, hasLength(1));
  });

  test('a revoked key ends quietly at setup', () async {
    await start();
    backend.acceptedKey = null;

    await events.load();

    expect(app.phase, ConnectionPhase.disconnected);
    expect(events.error, isNull);
  });

  group('read state', () {
    test('an event read under unread only leaves the list', () async {
      backend
        ..publish('e1', 'One', producer: ci)
        ..publish('e2', 'Two', producer: ci);
      await start();
      await events.setExtras(const InboxFilter(unreadOnly: true));

      final read = (await app.setRead('e1', read: true)).event!;
      events.replaceEvent(read);

      expect(events.events.map((e) => e.id), ['e2']);
    });

    test('an event marked unread again returns in its place', () async {
      backend
        ..publish('e1', 'One', producer: ci)
        ..publish('e2', 'Two', producer: ci)
        ..publish('e3', 'Three', producer: ci);
      await start();
      await events.setExtras(const InboxFilter(unreadOnly: true));
      events.replaceEvent((await app.setRead('e2', read: true)).event!);
      expect(events.events.map((e) => e.id), ['e3', 'e1']);

      events.replaceEvent((await app.setRead('e2', read: false)).event!);

      expect(events.events.map((e) => e.id), ['e3', 'e2', 'e1']);
    });

    test('hasUnread follows what is shown', () async {
      backend.publish('e1', 'One', producer: ci);
      await start();
      expect(events.hasUnread, isTrue);

      events.replaceEvent((await app.setRead('e1', read: true)).event!);

      expect(events.hasUnread, isFalse);
    });

    test('mark all as read reads this producer\'s events only', () async {
      backend
        ..publish('e1', 'Old backup', producer: backup)
        ..publish('e2', 'Old build', producer: ci)
        ..publish('e3', 'Newer backup', producer: backup)
        ..publish('e4', 'Newer build', producer: ci)
        ..publish('e5', 'Newest build', producer: ci);
      await start(pageSize: 2);

      final error = await events.markAllRead();

      expect(error, isNull);
      expect(events.events.map((e) => e.id), [
        'e5',
        'e4',
        'e2',
      ], reason: 'older pages were read to mark them too');
      expect(events.events.every((e) => e.isRead), isTrue);
      // The events of other producers, among them, are untouched.
      expect(backend.isRead('e1'), isFalse);
      expect(backend.isRead('e3'), isFalse);
      expect(backend.isRead('e2'), isTrue);
      expect(backend.isRead('e5'), isTrue);
      expect(
        backend.requests.where((r) => r.url.path == '/api/v1/events/read'),
        isEmpty,
        reason: 'the read-through call would also read other producers',
      );
    });

    test('mark all as read says when it could not', () async {
      backend.publish('e1', 'One', producer: ci);
      await start();
      backend.offline = true;

      final error = await events.markAllRead();

      expect(error, isNotNull);
      expect(events.markingAll, isFalse);
      expect(events.events.single.isRead, isFalse);
    });
  });

  test('does not notify once disposed', () async {
    backend.publish('e1', 'One', producer: ci);
    await app.start();
    final late = ProducerEventsController(gateway: app, producerId: 'p-ci');
    events = ProducerEventsController(gateway: app, producerId: 'p-ci');
    final pending = late.load();

    late.dispose();
    await pending;

    // Reaching here without "used after being disposed" is the check.
    expect(late.loaded, isTrue);
  });
}
