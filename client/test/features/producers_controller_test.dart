import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/app_controller.dart';
import 'package:signalhub_client/src/connection/server_credentials.dart';
import 'package:signalhub_client/src/features/producers_controller.dart';
import 'package:signalhub_client/src/models/users.dart';

import '../support/fakes.dart';
import '../support/producers_backend.dart';

void main() {
  late FakeBackend backend;
  late FakeProducers server;
  late InMemoryCredentialsStore store;
  late AppController app;

  setUp(() {
    backend = FakeBackend();
    server = FakeProducers(backend);
    store = InMemoryCredentialsStore()
      ..saved = ServerCredentials.parse(serverUrl, clientKey);
    app = AppController(
      store: store,
      apiFactory: (credentials) =>
          backend.api(credentials.baseUrl, credentials.clientKey),
      redeemPairing: backend.redeemPairing,
      push: FakePushService(),
    );
  });

  tearDown(() => app.dispose());

  Future<ProducersController> loaded() async {
    await app.start();
    await app.producers.load();
    return app.producers;
  }

  group('the list', () {
    test('merges what the user owns into the producers they see', () async {
      server
        ..addVisible('v1', 'ana-reports')
        ..addOwn('o1', 'ci-pipeline');

      final producers = await loaded();

      expect(producers.rows.map((r) => (r.name, r.isYours)), [
        ('ci-pipeline', true),
        ('ana-reports', false),
      ]);
      expect(server.visibleReads, 1);
      expect(server.ownReads, 1);
    });

    test('orders Yours, Subscribed and Can subscribe, each A to Z', () async {
      server
        ..addVisible('a', 'weather-alerts', subscribed: false)
        ..addVisible('b', 'Zebra-reports')
        ..addVisible('c', 'ana-reports')
        ..addVisible('d', 'price-watch', subscribed: false)
        ..addOwn('e', 'quarterly', subscribed: false)
        ..addOwn('f', 'Backup-jobs');

      final producers = await loaded();

      expect(producers.rows.map((r) => r.name), [
        'Backup-jobs',
        'quarterly',
        'ana-reports',
        'Zebra-reports',
        'price-watch',
        'weather-alerts',
      ]);
    });

    test(
      'lists a producer the user owns that is not listed as visible',
      () async {
        server.addOwn('o1', 'garage-door');
        server.visible.clear();

        final producers = await loaded();

        expect(producers.rows.single.name, 'garage-door');
        expect(producers.rows.single.isYours, isTrue);
      },
    );

    test('subscribed and byId serve the inbox filter', () async {
      server
        ..addVisible('a', 'ana-reports')
        ..addVisible('b', 'price-watch', subscribed: false);

      final producers = await loaded();

      expect(producers.subscribed.map((p) => p.name), ['ana-reports']);
      expect(producers.byId('b')?.name, 'price-watch');
      expect(producers.byId('missing'), isNull);
    });

    test('a failed read keeps the older list, and says why', () async {
      server.addVisible('a', 'ana-reports');
      final producers = await loaded();

      server.listFailure = 0;
      await producers.load();

      expect(producers.list.stale, isTrue);
      expect(producers.list.offline, isTrue);
      expect(producers.rows.single.name, 'ana-reports');

      server.listFailure = null;
      await producers.load();

      expect(producers.list.error, isNull);
    });

    test('a server error is not offline', () async {
      server.listFailure = 500;

      final producers = await loaded();

      expect(producers.list.failedWithoutList, isTrue);
      expect(producers.list.offline, isFalse);
    });

    test('a read that is running is not started again', () async {
      await app.start();
      server.holdLists = Completer();

      final first = app.producers.load();
      await app.producers.load();
      server.holdLists!.complete();
      await first;

      // Once at start of the first read, and not again for the second.
      expect(server.visibleReads, 1);
    });

    test('a revoked key ends quietly at setup', () async {
      await app.start();
      backend.acceptedKey = null;

      await app.producers.load();

      expect(app.phase, ConnectionPhase.disconnected);
    });
  });

  group('the row summary', () {
    Future<String> summaryOf(String name, {bool muted = false}) async {
      final producers = app.producers;
      return producers.rows
          .firstWhere((r) => r.name == name)
          .summary(mutedOnDevice: muted);
    }

    test('of a producer of the user', () async {
      server
        ..addOwn('1', 'public-two', keys: 2, lastEventAt: todayAt(1, 19))
        ..addOwn('2', 'public-one', lastEventAt: todayAt(0, 41))
        ..addOwn('3', 'with-revoked', keys: 1, revokedKeys: 2)
        ..addOwn(
          '4',
          'private-people',
          private: true,
          people: ['Ana', 'Bob'],
          lastEventAt: todayAt(0, 36),
        )
        ..addOwn('5', 'private-person', private: true, people: ['Ana'])
        ..addOwn('6', 'private-key', private: true);
      await loaded();

      expect(
        await summaryOf('public-two'),
        'Public · 2 keys · last event 01:19',
      );
      expect(
        await summaryOf('public-one'),
        'Public · 1 key · last event 00:41',
      );
      // Only the keys that still work are counted.
      expect(await summaryOf('with-revoked'), 'Public · 1 key · no events yet');
      expect(
        await summaryOf('private-people'),
        'Private · 2 people · last event 00:36',
      );
      expect(
        await summaryOf('private-person'),
        'Private · 1 person · no events yet',
      );
      expect(await summaryOf('private-key'), 'Private · 1 key · no events yet');
    });

    test('puts disabled producers last, in the same order', () async {
      server
        ..addVisible('a', 'weather-alerts', subscribed: false)
        ..addVisible('b', 'zebra-reports')
        ..addVisible('c', 'dead-feed', disabled: true)
        ..addOwn('d', 'quarterly')
        ..addOwn('e', 'Backup-jobs', paused: true)
        ..addOwn('f', 'old-sensor', disabledByHost: true);

      final producers = await loaded();

      expect(producers.rows.map((r) => r.name), [
        'quarterly',
        'zebra-reports',
        'weather-alerts',
        'Backup-jobs',
        'old-sensor',
        'dead-feed',
      ]);
    });

    test('of a producer that is paused or disabled', () async {
      server
        ..addOwn('1', 'paused', paused: true)
        ..addOwn('2', 'host', disabledByHost: true);
      await loaded();

      expect(
        await summaryOf('paused'),
        'Disabled by you · its keys do not work',
      );
      expect(await summaryOf('host'), 'Disabled by the host · ask the host');
      expect(
        app.producers.rows.firstWhere((r) => r.name == 'paused').disabledByYou,
        isTrue,
      );
      expect(
        app.producers.rows.firstWhere((r) => r.name == 'host').disabledByHost,
        isTrue,
      );
    });

    test('of somebody else\'s producer', () async {
      server
        ..addVisible('1', 'public')
        ..addVisible('2', 'shared', private: true)
        ..addVisible('3', 'off', owner: 'João', disabled: true);
      await loaded();

      expect(await summaryOf('public'), 'Ana · Public');
      expect(await summaryOf('shared'), 'Ana · Private, shared with you');
      expect(await summaryOf('off'), 'João · Disabled');
    });

    test(
      'says when this device mutes a producer it is subscribed to',
      () async {
        server
          ..addVisible('1', 'public')
          ..addVisible('2', 'not-subscribed', subscribed: false);
        await loaded();

        expect(
          await summaryOf('public', muted: true),
          'Ana · Public · Muted on this device',
        );
        expect(await summaryOf('not-subscribed', muted: true), 'Ana · Public');
      },
    );

    test('last event is the time today and the date before', () {
      final now = DateTime(2026, 10, 10, 12);

      expect(formatLastEvent(DateTime(2026, 10, 10, 1, 19), now: now), '01:19');
      expect(
        formatLastEvent(DateTime(2026, 10, 9, 23, 5), now: now),
        '2026-10-09 23:05',
      );
    });
  });

  group('subscribing', () {
    test('subscribes in place, and says it is running meanwhile', () async {
      server.addVisible('a', 'price-watch', subscribed: false);
      final producers = await loaded();
      server.holdSubscriptions = Completer();

      final change = producers.setSubscribed('a', subscribed: true);
      await pumpEventQueue();
      expect(producers.isChanging('a'), isTrue);
      expect(producers.changingTo('a'), isTrue);
      // Another change to it is ignored meanwhile.
      expect(
        await producers.setSubscribed('a', subscribed: false),
        SubscriptionOutcome.ignored,
      );
      server.holdSubscriptions!.complete();

      expect(await change, SubscriptionOutcome.changed);
      expect(producers.isChanging('a'), isFalse);
      expect(producers.byId('a')!.subscribed, isTrue);
      expect(server.subscriptionCalls, ['PUT a']);
    });

    test('unsubscribes from a producer of the user', () async {
      server.addOwn('o', 'ci-pipeline');
      final producers = await loaded();

      final outcome = await producers.setSubscribed('o', subscribed: false);

      expect(outcome, SubscriptionOutcome.changed);
      expect(producers.rows.single.subscribed, isFalse);
      expect(producers.rows.single.isYours, isTrue);
      expect(server.subscriptionCalls, ['DELETE o']);
    });

    test('a failure leaves the producer as it was', () async {
      server.addVisible('a', 'ana-reports');
      final producers = await loaded();
      server.subscribeFailures['a'] = 500;

      final outcome = await producers.setSubscribed('a', subscribed: false);

      expect(outcome, SubscriptionOutcome.failed);
      expect(producers.byId('a')!.subscribed, isTrue);
      expect(producers.isChanging('a'), isFalse);
    });

    test('no answer at all is a failure too', () async {
      server.addVisible('a', 'ana-reports');
      final producers = await loaded();
      server.subscribeFailures['a'] = null;

      expect(
        await producers.setSubscribed('a', subscribed: false),
        SubscriptionOutcome.failed,
      );
    });

    test('a producer that is gone leaves the list', () async {
      server
        ..addVisible('a', 'ana-reports')
        ..addOwn('o', 'ci-pipeline');
      final producers = await loaded();
      server.subscribeFailures['a'] = 404;

      final outcome = await producers.setSubscribed('a', subscribed: false);

      expect(outcome, SubscriptionOutcome.gone);
      expect(producers.rows.map((r) => r.name), ['ci-pipeline']);
    });

    test('a revoked key ends quietly at setup', () async {
      server.addVisible('a', 'ana-reports');
      final producers = await loaded();
      backend.acceptedKey = null;

      final outcome = await producers.setSubscribed('a', subscribed: false);

      expect(outcome, SubscriptionOutcome.ignored);
      expect(app.phase, ConnectionPhase.disconnected);
    });

    test('a refusal reads the role again and fails', () async {
      server.addVisible('a', 'ana-reports');
      final producers = await loaded();
      expect(app.role, UserRole.basic);
      backend.userRole = 'MOD';
      server.subscribeFailures['a'] = 403;

      final outcome = await producers.setSubscribed('a', subscribed: false);

      expect(outcome, SubscriptionOutcome.failed);
      expect(app.role, UserRole.mod);
    });

    test('an unknown producer is not asked about', () async {
      final producers = await loaded();

      expect(
        await producers.setSubscribed('missing', subscribed: true),
        SubscriptionOutcome.ignored,
      );
      expect(server.subscriptionCalls, isEmpty);
    });
  });

  test('does not notify once disposed', () async {
    server.addVisible('a', 'ana-reports', subscribed: false);
    await app.start();
    final producers = app.producers;
    server.holdLists = Completer();

    final read = producers.load();
    app.dispose();
    server.holdLists!.complete();
    await read;

    // Reaching here without "used after being disposed" is the check.
    app = AppController(
      store: store,
      apiFactory: (credentials) =>
          backend.api(credentials.baseUrl, credentials.clientKey),
      redeemPairing: backend.redeemPairing,
    );
  });
}
