import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:signalhub_client/src/api/signalhub_api.dart';
import 'package:signalhub_client/src/api_gateway.dart';
import 'package:signalhub_client/src/app_controller.dart';
import 'package:signalhub_client/src/connection/server_credentials.dart';
import 'package:signalhub_client/src/connection/setup_failure.dart';
import 'package:signalhub_client/src/models/inbox_filter.dart';
import 'package:signalhub_client/src/onboarding/onboarding_store.dart';
import 'package:signalhub_client/src/push/firebase_push_service.dart';
import 'package:signalhub_client/src/push/push_service.dart';

import 'support/fakes.dart';
import 'support/first_run_support.dart';

void main() {
  late FakeBackend backend;
  late FakePushService push;
  late InMemoryCredentialsStore store;
  late InMemoryOnboardingStore onboarding;

  setUp(() {
    backend = FakeBackend()
      ..userName = 'Rui'
      ..publish('e-1', 'Build failed');
    push = FakePushService();
    store = InMemoryCredentialsStore();
    onboarding = InMemoryOnboardingStore();
  });

  AppController controller({bool withOnboarding = true}) => AppController(
    store: store,
    apiFactory: (credentials) =>
        backend.api(credentials.baseUrl, credentials.clientKey),
    redeemPairing: backend.redeemPairing,
    push: push,
    onboarding: withOnboarding ? onboarding : null,
  );

  group('the welcome and what\'s new', () {
    test('a device that connects with a client key gets the welcome', () async {
      final app = controller();

      await app.connect(serverUrl, clientKey);

      expect(app.onboarding, OnboardingStep.welcome);
      expect(onboarding.saved, OnboardingStep.welcome);
    });

    test('a device that pairs gets the welcome', () async {
      backend
        ..acceptedKey = null
        ..pairingCodes.add(pairingCode);
      final app = controller();

      await app.pair(pairingUri);

      expect(app.onboarding, OnboardingStep.welcome);
    });

    test('a failed attempt says nothing', () async {
      backend.acceptedKey = 'shck1_other';
      final app = controller();

      await app.connect(serverUrl, clientKey);

      expect(app.onboarding, OnboardingStep.done);
      expect(onboarding.saved, isNull);
    });

    test('a device that starts with credentials and no record gets what\'s '
        'new', () async {
      store.saved = ServerCredentials.parse(serverUrl, clientKey);
      final app = controller();

      await app.start();

      expect(app.onboarding, OnboardingStep.whatsNew);
    });

    test('a device that starts with a record has what it recorded', () async {
      store.saved = ServerCredentials.parse(serverUrl, clientKey);
      for (final step in OnboardingStep.values) {
        onboarding.saved = step;
        push = FakePushService();
        final app = controller();

        await app.start();

        expect(app.onboarding, step);
      }
    });

    test('a device without saved credentials has nothing to say', () async {
      final app = controller();

      await app.start();

      expect(app.onboarding, OnboardingStep.done);
    });

    test('without a store the app says neither', () async {
      store.saved = ServerCredentials.parse(serverUrl, clientKey);
      final app = controller(withOnboarding: false);

      await app.start();
      await app.connect(serverUrl, clientKey);

      expect(app.onboarding, OnboardingStep.done);
    });

    test('a store that cannot be read counts as nothing to say', () async {
      store.saved = ServerCredentials.parse(serverUrl, clientKey);
      onboarding.fails = true;
      final app = controller();

      await app.start();

      expect(app.onboarding, OnboardingStep.done);
      expect(app.phase, ConnectionPhase.connected);
    });

    test('finishing the welcome keeps that, and can open Producers', () async {
      final app = controller();
      await app.connect(serverUrl, clientKey);

      await app.finishWelcome(findProducers: true);

      expect(app.onboarding, OnboardingStep.done);
      expect(app.tab, HomeTab.producers);
      expect(onboarding.saved, OnboardingStep.done);
    });

    test('the welcome and what\'s new end only their own step', () async {
      final app = controller();
      await app.connect(serverUrl, clientKey);

      await app.dismissWhatsNew(seeProducers: true);

      expect(app.onboarding, OnboardingStep.welcome);
      expect(app.tab, HomeTab.inbox);
    });

    test('dismissing what\'s new keeps that, and can open Producers', () async {
      store.saved = ServerCredentials.parse(serverUrl, clientKey);
      final app = controller();
      await app.start();

      await app.dismissWhatsNew(seeProducers: true);

      expect(app.onboarding, OnboardingStep.done);
      expect(app.tab, HomeTab.producers);
      expect(onboarding.saved, OnboardingStep.done);
    });

    test('not being able to keep the step changes nothing else', () async {
      final app = controller();
      await app.connect(serverUrl, clientKey);
      onboarding.fails = true;

      await app.finishWelcome();

      expect(app.onboarding, OnboardingStep.done);
    });

    test(
      'disconnecting forgets the step in the app, not on the device',
      () async {
        final app = controller();
        await app.connect(serverUrl, clientKey);

        await app.disconnect();

        expect(app.onboarding, OnboardingStep.done);
        expect(app.signedOut, isFalse);
      },
    );
  });

  group('a device the server no longer accepts', () {
    test('goes back to setup at once, with the old state dropped', () async {
      final app = controller();
      await app.connect(serverUrl, clientKey);
      var calls = 0;
      final snapshots = <(ConnectionPhase, int, bool)>[];
      app.addListener(() {
        calls++;
        snapshots.add((app.phase, app.events.length, app.registration == null));
      });
      backend.acceptedKey = null;

      await app.refresh();

      // The first thing anyone is told is that it is at setup, with nothing
      // of the old connection left to draw.
      expect(snapshots.first, (ConnectionPhase.disconnected, 0, true));
      expect(calls, 1);
      expect(app.signedOut, isTrue);
      expect(app.error, isNull);
      expect(store.saved, isNull);
    });

    test(
      'any request ends it the same way, even the one for an event',
      () async {
        final app = controller();
        await app.connect(serverUrl, clientKey);
        backend.acceptedKey = null;
        backend.events.clear();

        await expectLater(
          app.event('e-gone'),
          throwsA(isA<SignedOutException>()),
        );

        expect(app.phase, ConnectionPhase.disconnected);
        expect(app.signedOut, isTrue);
      },
    );

    test('a new connection clears it', () async {
      final app = controller();
      await app.connect(serverUrl, clientKey);
      backend.acceptedKey = null;
      await app.refresh();
      backend.acceptedKey = clientKey;

      await app.connect(serverUrl, clientKey);

      expect(app.signedOut, isFalse);
      expect(app.phase, ConnectionPhase.connected);
    });

    test('the neutral sentence is the one decided', () {
      expect(
        noLongerConnectedMessage,
        'This device is no longer connected to SignalHub. To use it again, '
        'ask for a new code, or ask the host.',
      );
    });

    test('a start with a revoked key says so as well', () async {
      store.saved = ServerCredentials.parse(serverUrl, clientKey);
      backend.acceptedKey = null;
      final app = controller();

      await app.start();

      expect(app.signedOut, isTrue);
      expect(app.onboarding, OnboardingStep.done);
    });
  });

  group('connecting fails with a reason', () {
    test('a link that is not an invitation, and the sign-in code of a web '
        'page', () async {
      final app = controller();

      expect(
        (await app.pair('https://example.org'))?.kind,
        SetupFailureKind.notInvitation,
      );
      expect(
        (await app.pair('signalhub://signin?code=K7Q-4MX'))?.kind,
        SetupFailureKind.webSignIn,
      );
      expect((await app.pair(clientKey))?.kind, SetupFailureKind.notInvitation);
      expect(backend.requests, isEmpty);
    });

    test('a code that does not work', () async {
      backend.acceptedKey = null;
      final app = controller();

      final failure = await app.pair(pairingUri);

      expect(failure?.kind, SetupFailureKind.codeRejected);
      expect(failure?.canRetry, isFalse);
    });

    test('a server that cannot be reached is named by its address', () async {
      backend.offline = true;
      final app = controller();

      final failure = await app.connect('https://hub.example:8443', clientKey);

      expect(failure?.kind, SetupFailureKind.unreachable);
      expect(failure?.message, startsWith("Can't reach hub.example:8443."));
      expect(failure?.canRetry, isTrue);
    });

    test('a server that answers with an error', () async {
      final app = controller();
      backend.handlers.add((request, path) {
        if (path != '/api/v1/client') return null;
        return http.Response(
          '{"title":"Server error","status":500}',
          500,
          headers: {'content-type': 'application/json'},
        );
      });

      final failure = await app.connect(serverUrl, clientKey);

      expect(failure?.kind, SetupFailureKind.serverProblem);
      expect(failure?.canRetry, isTrue);
    });

    test(
      'a key the server does not accept, and input that is not one',
      () async {
        backend.acceptedKey = 'shck1_other';
        final app = controller();

        expect(
          (await app.connect(serverUrl, clientKey))?.kind,
          SetupFailureKind.keyRejected,
        );
        expect(
          (await app.connect(serverUrl, 'nope'))?.kind,
          SetupFailureKind.badKey,
        );
        expect(
          (await app.connect('nope', clientKey))?.kind,
          SetupFailureKind.badAddress,
        );
      },
    );

    test('an answer that cannot be read', () async {
      final app = AppController(
        store: store,
        apiFactory: (credentials) =>
            backend.api(credentials.baseUrl, credentials.clientKey),
        redeemPairing: (url, code) async => throw const FormatException('x'),
        push: push,
      );

      expect(
        (await app.pair(pairingUri))?.kind,
        SetupFailureKind.unexpectedAnswer,
      );
    });
  });

  group('an event that is not in the inbox any more', () {
    test('is taken out of the list when the server says so', () async {
      backend.publish('e-2', 'Disk full');
      final app = controller();
      await app.connect(serverUrl, clientKey);
      expect(app.unreadCount, 2);
      backend.events.removeWhere((e) => e['id'] == 'e-1');

      final read = await app.markRead('e-1');

      expect(read.error, const EventNotFoundException().message);
      expect(app.events.map((e) => e.id), ['e-2']);
      expect(app.unreadCount, 1);
    });

    test('is also taken out when it is opened from the server', () async {
      final app = controller();
      await app.connect(serverUrl, clientKey);
      await app.setFilter(const InboxFilter(unreadOnly: true));
      backend.events.clear();

      await expectLater(
        app.event('e-gone'),
        throwsA(isA<EventNotFoundException>()),
      );

      expect(app.phase, ConnectionPhase.connected);
    });

    test(
      'a read-state change of one that is gone says so, and drops it',
      () async {
        final app = controller();
        await app.connect(serverUrl, clientKey);
        backend.events.clear();

        final changed = await app.setRead('e-1', read: false);

        expect(changed.event, isNull);
        expect(changed.error, const EventNotFoundException().message);
        expect(app.events, isEmpty);
      },
    );
  });

  group('notices about a device', () {
    test('an opened one is for the devices, not an event', () async {
      final app = controller();
      await app.connect(serverUrl, clientKey);

      push.received.add(
        const PushNotice(
          title: 'New device paired',
          opened: true,
          data: {'notice': 'client-paired'},
        ),
      );
      await pumpEventQueue();

      expect(app.takeDeviceNoticeToOpen(), isTrue);
      expect(app.takeDeviceNoticeToOpen(), isFalse);
      expect(app.takeEventToOpen(), isNull);
    });

    test('one that is not opened asks for nothing', () async {
      final app = controller();
      await app.connect(serverUrl, clientKey);

      push.received.add(
        const PushNotice(title: 'x', data: {'notice': 'client-revoked'}),
      );
      await pumpEventQueue();

      expect(app.takeDeviceNoticeToOpen(), isFalse);
    });

    test('an event push is for the event', () async {
      final app = controller();
      await app.connect(serverUrl, clientKey);

      push.received.add(
        const PushNotice(title: 'Build failed', eventId: 'e-1', opened: true),
      );
      await pumpEventQueue();

      expect(app.takeEventToOpen(), 'e-1');
      expect(app.takeDeviceNoticeToOpen(), isFalse);
    });

    test(
      'a notice that was tapped before the device was set up is forgotten',
      () async {
        final app = controller();
        push.received.add(
          const PushNotice(
            title: 'x',
            opened: true,
            data: {'notice': 'client-paired'},
          ),
        );

        await app.start();

        expect(app.takeDeviceNoticeToOpen(), isFalse);
      },
    );

    test(
      'the provider\'s message keeps its data, and says if it is a notice',
      () {
        final notice = FirebasePushService.noticeOf(
          const RemoteMessage(
            notification: RemoteNotification(
              title: 'New device paired',
              body: 'b',
            ),
            data: {'notice': 'client-paired', 'clientId': 'c-9'},
          ),
          true,
        );
        final event = FirebasePushService.noticeOf(
          const RemoteMessage(
            notification: RemoteNotification(title: 'Build failed'),
            data: {'eventId': 'e-1', 'category': 'BLOCKED', 'severity': 'HIGH'},
          ),
          false,
        );

        expect(notice.notice, 'client-paired');
        expect(notice.eventId, isNull);
        expect(notice.opened, isTrue);
        expect(notice.data['clientId'], 'c-9');
        expect(event.notice, isNull);
        expect(event.eventId, 'e-1');
      },
    );
  });

  group('the producers to choose from', () {
    test('a producer\'s name is the one this user sees, or else an '
        'event\'s', () async {
      FakeVisibleProducers()
        ..add('p-9', 'ana-reports')
        ..install(backend);
      final app = controller();
      await app.connect(serverUrl, clientKey);
      await app.producers.load();

      expect(app.producerName('p-9'), 'ana-reports');
      expect(app.producerName('p-1'), 'nightly-build');
      expect(app.producerName('p-0'), isNull);
    });
  });
}
