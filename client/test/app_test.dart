import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/api/signalhub_api.dart';
import 'package:signalhub_client/src/app.dart';
import 'package:signalhub_client/src/app_controller.dart';
import 'package:signalhub_client/src/build_identity.dart';
import 'package:signalhub_client/src/connection/pairing_uri.dart';
import 'package:signalhub_client/src/push/push_registration.dart';
import 'package:signalhub_client/src/push/push_service.dart';
import 'package:signalhub_client/src/ui/connect_device_screen.dart';

import 'support/fakes.dart';

void main() {
  late FakeBackend backend;
  late FakePushService push;
  late AppController controller;

  /// The links the app handed to the platform, and whether it opens them.
  late List<Uri> openedLinks;
  late bool linksOpen;

  setUp(() {
    openedLinks = [];
    linksOpen = true;
    backend = FakeBackend()..publish('e-1', 'Nightly build failed');
    push = FakePushService();
    controller = AppController(
      store: InMemoryCredentialsStore(),
      apiFactory: (credentials) =>
          backend.api(credentials.baseUrl, credentials.clientKey),
      redeemPairing: backend.redeemPairing,
      push: push,
    );
  });

  Future<void> connect(WidgetTester tester, {String key = clientKey}) async {
    await tester.pumpWidget(
      SignalHubApp(
        controller: controller,
        linkOpener: (link) async {
          openedLinks.add(link);
          return linksOpen;
        },
      ),
    );
    await tester.runAsync(controller.start);
    await tester.pump();
    // Manual setup comes after pairing, below the fold.
    await tester.ensureVisible(find.byKey(const Key('connect')));
    await tester.enterText(find.byKey(const Key('serverUrl')), serverUrl);
    await tester.enterText(find.byKey(const Key('clientKey')), key);
    await tester.tap(find.byKey(const Key('connect')));
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
  }

  testWidgets('sets up a device and shows its inbox', (tester) async {
    await connect(tester);

    expect(find.text('Nightly build failed'), findsOneWidget);
    expect(find.text('Blocked · High · nightly-build'), findsOneWidget);
  });

  group('pairing', () {
    setUp(() {
      backend
        ..acceptedKey = null
        ..pairingCodes.add(pairingCode);
    });

    Future<void> showSetup(
      WidgetTester tester, {
      String? scanned,
      void Function()? onScan,
    }) async {
      await tester.pumpWidget(
        SignalHubApp(
          controller: controller,
          scanner: (context) async {
            onScan?.call();
            return scanned;
          },
        ),
      );
      await tester.runAsync(controller.start);
      await tester.pump();
    }

    testWidgets('a scanned code sets up the device', (tester) async {
      await showSetup(tester, scanned: pairingUri);

      await tester.tap(find.byKey(const Key('scanPairing')));
      await settle(tester);

      expect(find.text('Nightly build failed'), findsOneWidget);
      expect(backend.acceptedKey, pairedClientKey);
    });

    testWidgets('going back from the scanner stays on setup', (tester) async {
      var scans = 0;
      await showSetup(tester, onScan: () => scans++);

      await tester.tap(find.byKey(const Key('scanPairing')));
      await settle(tester);

      expect(scans, 1);
      expect(find.byKey(const Key('pairingUri')), findsOneWidget);
      expect(backend.requests, isEmpty);
    });

    testWidgets('a pasted link sets up the device', (tester) async {
      await showSetup(tester);

      await tester.enterText(find.byKey(const Key('pairingUri')), pairingUri);
      await tester.tap(find.byKey(const Key('pair')));
      await settle(tester);

      expect(find.text('Nightly build failed'), findsOneWidget);
    });

    testWidgets('an expired or used code says so', (tester) async {
      backend.pairingCodes.clear();
      await showSetup(tester, scanned: pairingUri);

      await tester.tap(find.byKey(const Key('scanPairing')));
      await settle(tester);

      expect(
        find.text(const PairingRejectedException().message),
        findsOneWidget,
      );
    });

    testWidgets('an unreachable server says so', (tester) async {
      backend.offline = true;
      await showSetup(tester, scanned: pairingUri);

      await tester.tap(find.byKey(const Key('scanPairing')));
      await settle(tester);

      expect(
        find.text('Could not reach the server ($serverUrl)'),
        findsOneWidget,
      );
    });

    testWidgets('another QR code is not taken for a pairing code', (
      tester,
    ) async {
      await showSetup(tester, scanned: 'https://example.org');

      await tester.tap(find.byKey(const Key('scanPairing')));
      await settle(tester);

      expect(find.text(PairingUri.invalid), findsOneWidget);
      expect(backend.requests, isEmpty);
    });
  });

  testWidgets('an unreachable server is the one message shown', (tester) async {
    await connect(tester);
    backend.offline = true;

    // Pull to refresh.
    await tester.runAsync(controller.refresh);
    await tester.pumpAndSettle();

    expect(find.text('Could not reach the server'), findsOneWidget);
    expect(find.text(PushStatus.failed.description), findsNothing);
  });

  testWidgets('a failed push registration is shown when the server answers', (
    tester,
  ) async {
    push.token = null;

    await connect(tester);

    expect(find.text(PushStatus.failed.description), findsOneWidget);
  });

  Future<void> openDevice(WidgetTester tester) async {
    await tester.tap(find.byType(PopupMenuButton<void>));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('device')));
    await tester.pumpAndSettle();
  }

  AppController controllerOf(BuildIdentity build) => AppController(
    store: InMemoryCredentialsStore(),
    apiFactory: (credentials) =>
        backend.api(credentials.baseUrl, credentials.clientKey),
    redeemPairing: backend.redeemPairing,
    push: push = FakePushService(),
    build: build,
  );

  const revision = '0123456789abcdef0123456789abcdef01234567';

  Finder buildEntry(String text) => find.descendant(
    of: find.byKey(const Key('build')),
    matching: find.text(text),
  );

  testWidgets('shows this device and its push status', (tester) async {
    await connect(tester);

    await openDevice(tester);

    expect(find.text('Pixel 8'), findsOneWidget);
    expect(find.text(serverUrl), findsOneWidget);
    expect(find.text('Push notifications are on'), findsOneWidget);
  });

  AppController servedPushController(FakeServedPushStarter starter) =>
      AppController(
        store: InMemoryCredentialsStore(),
        apiFactory: (credentials) =>
            backend.api(credentials.baseUrl, credentials.clientKey),
        redeemPairing: backend.redeemPairing,
        startServedPush: starter.call,
      );

  testWidgets('a build without push options takes the server\'s', (
    tester,
  ) async {
    backend.pushConfig = servedPushConfig;
    controller = servedPushController(FakeServedPushStarter());
    await connect(tester);

    await openDevice(tester);

    expect(find.text('Push notifications are on'), findsOneWidget);
    expect(backend.pushToken, 'device-token-1');
  });

  testWidgets('a server without push options says so', (tester) async {
    controller = servedPushController(FakeServedPushStarter());
    await connect(tester);

    await openDevice(tester);

    expect(find.text('Push is not configured on this server'), findsOneWidget);
  });

  testWidgets('options that do not work are shown in the inbox', (
    tester,
  ) async {
    backend.pushConfig = servedPushConfig;
    controller = servedPushController(FakeServedPushStarter()..accepts = false);

    await connect(tester);

    expect(
      find.text("This server's push configuration does not work with this app"),
      findsOneWidget,
    );
  });

  testWidgets('a release build shows its version and commit', (tester) async {
    controller = controllerOf(
      const BuildIdentity(version: '1.4.0', revision: revision),
    );
    await connect(tester);

    await openDevice(tester);

    expect(buildEntry('SignalHub 1.4.0'), findsOneWidget);
    expect(buildEntry('Commit 0123456'), findsOneWidget);
  });

  testWidgets('a build with only its commit is a development build', (
    tester,
  ) async {
    controller = controllerOf(const BuildIdentity(revision: revision));
    await connect(tester);

    await openDevice(tester);

    expect(buildEntry('SignalHub development build'), findsOneWidget);
    expect(buildEntry('Commit 0123456'), findsOneWidget);
  });

  testWidgets('a build given neither says its commit is unknown', (
    tester,
  ) async {
    controller = controllerOf(const BuildIdentity());
    await connect(tester);

    await openDevice(tester);

    expect(buildEntry('SignalHub development build'), findsOneWidget);
    expect(buildEntry('Commit unknown'), findsOneWidget);
  });

  testWidgets('the build entry never shows the pubspec placeholder', (
    tester,
  ) async {
    final placeholder = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1)!;
    await connect(tester);

    await openDevice(tester);

    final placeholderName = placeholder.split('+').first;
    expect(find.textContaining(placeholderName), findsNothing);
    expect(buildEntry('SignalHub development build'), findsOneWidget);
    expect(buildEntry('Commit unknown'), findsOneWidget);
  });

  testWidgets('an empty inbox says so', (tester) async {
    backend.events.clear();

    await connect(tester);

    expect(find.text('No events yet'), findsOneWidget);
  });

  testWidgets('tapping an event shows all of it', (tester) async {
    backend.publish(
      'e-2',
      'Deploy done',
      message: 'v1.2.3 is live.',
      context: 'homelab',
    );
    await connect(tester);

    await tester.tap(find.text('Deploy done'));
    await tester.pumpAndSettle();

    expect(find.text('v1.2.3 is live.'), findsOneWidget);
    expect(find.text('Blocked'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    expect(find.text('nightly-build'), findsOneWidget);
    expect(find.text('homelab'), findsOneWidget);
    expect(find.text('e-2'), findsOneWidget);
    // Metadata is shown as the producer sent it.
    expect(find.text('{\n  "run": 7\n}'), findsOneWidget);
  });

  group('an event\'s link', () {
    const link = 'https://ci.example.com/runs/1842';

    Finder linkIcon(String title) => find.descendant(
      of: find.widgetWithText(ListTile, title),
      matching: find.byKey(const Key('hasLink')),
    );

    testWidgets('is shown on its screen and opened with one tap', (
      tester,
    ) async {
      backend.publish('e-2', 'Build failed', link: link);
      await connect(tester);

      await tester.tap(find.text('Build failed'));
      await settle(tester);

      // The action is labelled, and the address is shown before it is used.
      expect(find.text('Open link'), findsOneWidget);
      expect(find.text(link), findsOneWidget);
      expect(openedLinks, isEmpty);

      await tester.tap(find.byKey(const Key('openLink')));
      await settle(tester);

      expect(openedLinks, [Uri.parse(link)]);
      // Still on the event.
      expect(find.text('e-2'), findsOneWidget);
      expect(find.text('Could not open the link'), findsNothing);
    });

    testWidgets('that cannot be opened says so and stays on the event', (
      tester,
    ) async {
      linksOpen = false;
      backend.publish('e-2', 'Build failed', link: link);
      await connect(tester);
      await tester.tap(find.text('Build failed'));
      await settle(tester);

      await tester.tap(find.byKey(const Key('openLink')));
      await settle(tester);

      expect(find.text('Could not open the link'), findsOneWidget);
      expect(find.text('e-2'), findsOneWidget);
      expect(find.byKey(const Key('openLink')), findsOneWidget);
    });

    testWidgets('is marked in the inbox, and the row opens the event', (
      tester,
    ) async {
      backend.publish('e-2', 'Build failed', link: link);
      await connect(tester);

      expect(linkIcon('Build failed'), findsOneWidget);
      expect(linkIcon('Nightly build failed'), findsNothing);

      await tester.tap(find.text('Build failed'));
      await settle(tester);

      expect(openedLinks, isEmpty);
      expect(find.byKey(const Key('openLink')), findsOneWidget);
    });

    testWidgets('is not opened by tapping its notification', (tester) async {
      await connect(tester);
      backend.publish('e-2', 'Build failed', link: link);

      push.received.add(
        const PushNotice(title: 'Build failed', eventId: 'e-2', opened: true),
      );
      await settle(tester);

      expect(find.text('e-2'), findsOneWidget);
      expect(find.byKey(const Key('openLink')), findsOneWidget);
      expect(openedLinks, isEmpty);
    });

    testWidgets('that the app cannot open is not offered', (tester) async {
      backend.publish('e-2', 'Build failed', link: 'javascript:alert(1)');
      await connect(tester);

      expect(linkIcon('Build failed'), findsNothing);
      await tester.tap(find.text('Build failed'));
      await settle(tester);

      expect(find.text('e-2'), findsOneWidget);
      expect(find.byKey(const Key('openLink')), findsNothing);
      expect(find.text('javascript:alert(1)'), findsNothing);
    });

    testWidgets('is absent from an older server\'s events', (tester) async {
      backend.events.single.remove('link');
      await connect(tester);

      expect(linkIcon('Nightly build failed'), findsNothing);
      await tester.tap(find.text('Nightly build failed'));
      await settle(tester);

      expect(find.text('e-1'), findsOneWidget);
      expect(find.byKey(const Key('openLink')), findsNothing);
      expect(find.text('Link'), findsNothing);
    });
  });

  testWidgets('scrolling down loads older events', (tester) async {
    for (var i = 2; i <= AppController.pageSize + 5; i++) {
      backend.publish('e-$i', 'Event $i');
    }
    await connect(tester);
    expect(find.text('Nightly build failed'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Nightly build failed'),
      500,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Nightly build failed'), findsOneWidget);
    expect(controller.hasMore, isFalse);
  });

  testWidgets('a failed older page can be retried', (tester) async {
    for (var i = 2; i <= AppController.pageSize + 1; i++) {
      backend.publish('e-$i', 'Event $i');
    }
    await connect(tester);
    backend.offline = true;

    await tester.scrollUntilVisible(
      find.byKey(const Key('loadMoreRetry')),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    backend.offline = false;
    await tester.tap(find.byKey(const Key('loadMoreRetry')));
    await settle(tester);

    expect(find.text('Nightly build failed'), findsOneWidget);
  });

  Finder unreadDot(String title) => find.descendant(
    of: find.widgetWithText(ListTile, title),
    matching: find.byKey(const Key('unread')),
  );

  testWidgets('shows which events are unread and how many', (tester) async {
    backend
      ..publish('e-2', 'Seen', readAt: '2026-09-25T12:04:00Z')
      ..publish('e-3', 'Deploy done');

    await connect(tester);

    expect(unreadDot('Nightly build failed'), findsOneWidget);
    expect(unreadDot('Deploy done'), findsOneWidget);
    expect(unreadDot('Seen'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('unreadCount')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('opening an event marks it read', (tester) async {
    await connect(tester);

    await tester.tap(find.text('Nightly build failed'));
    await settle(tester);
    expect(backend.isRead('e-1'), isTrue);
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(unreadDot('Nightly build failed'), findsNothing);
    expect(find.byKey(const Key('unreadCount')), findsNothing);
  });

  testWidgets('an event can be marked unread again', (tester) async {
    backend.events.single['readAt'] = '2026-09-25T12:04:00Z';
    await connect(tester);

    await tester.tap(find.text('Nightly build failed'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('markUnread')));
    await settle(tester);

    // Back in the inbox, unread.
    expect(find.byKey(const Key('markUnread')), findsNothing);
    expect(backend.isRead('e-1'), isFalse);
    expect(unreadDot('Nightly build failed'), findsOneWidget);
  });

  Finder unreadCount(String count) => find.descendant(
    of: find.byKey(const Key('unreadCount')),
    matching: find.text(count),
  );

  testWidgets('an opened event offers to mark it unread', (tester) async {
    await connect(tester);

    await tester.tap(find.text('Nightly build failed'));
    await settle(tester);

    // The server's answer to marking it read on opening.
    expect(find.byKey(const Key('markUnread')), findsOneWidget);
    expect(find.byKey(const Key('markRead')), findsNothing);
    expect(find.text('Mark as unread'), findsOneWidget);
    expect(find.text('Unread'), findsNothing);
  });

  testWidgets('an event not marked read on opening can be marked read', (
    tester,
  ) async {
    await connect(tester);
    backend.offline = true;

    await tester.tap(find.text('Nightly build failed'));
    await settle(tester);

    // Marking on opening failed: still unread, a message says so, and the
    // action offers to mark it read.
    expect(backend.isRead('e-1'), isFalse);
    expect(find.text('Unread'), findsOneWidget);
    expect(
      find.text('Not marked as read: Could not reach the server'),
      findsOneWidget,
    );
    expect(find.text('Mark as read'), findsOneWidget);
    expect(find.byKey(const Key('markUnread')), findsNothing);

    backend.offline = false;
    await tester.tap(find.byKey(const Key('markRead')));
    await settle(tester);

    // Still on the event, now read.
    expect(backend.isRead('e-1'), isTrue);
    expect(find.text('Unread'), findsNothing);
    expect(find.byKey(const Key('markUnread')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(unreadDot('Nightly build failed'), findsNothing);
    expect(find.byKey(const Key('unreadCount')), findsNothing);
  });

  testWidgets('a failed mark read says why and changes nothing', (
    tester,
  ) async {
    await connect(tester);
    backend.offline = true;

    await tester.tap(find.text('Nightly build failed'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('markRead')));
    await settle(tester);

    expect(find.text('Could not reach the server'), findsOneWidget);
    expect(find.byKey(const Key('markRead')), findsOneWidget);
    expect(find.text('Unread'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(unreadDot('Nightly build failed'), findsOneWidget);
    expect(unreadCount('1'), findsOneWidget);
  });

  testWidgets('a failed mark unread says why and changes nothing', (
    tester,
  ) async {
    backend.events.single['readAt'] = '2026-09-25T12:04:00Z';
    await connect(tester);

    await tester.tap(find.text('Nightly build failed'));
    await settle(tester);
    backend.offline = true;
    await tester.tap(find.byKey(const Key('markUnread')));
    await settle(tester);

    expect(find.text('Could not reach the server'), findsOneWidget);
    expect(find.byKey(const Key('markUnread')), findsOneWidget);
    expect(backend.isRead('e-1'), isTrue);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(unreadDot('Nightly build failed'), findsNothing);
  });

  testWidgets('marking unread updates the unread count', (tester) async {
    await connect(tester);
    expect(unreadCount('1'), findsOneWidget);

    await tester.tap(find.text('Nightly build failed'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('markUnread')));
    await settle(tester);

    expect(backend.isRead('e-1'), isFalse);
    expect(unreadDot('Nightly build failed'), findsOneWidget);
    expect(unreadCount('1'), findsOneWidget);
  });

  testWidgets('marks everything shown read', (tester) async {
    backend.publish('e-2', 'Deploy done');
    await connect(tester);

    await tester.tap(find.byKey(const Key('markAllRead')));
    await settle(tester);

    expect(backend.isRead('e-1') && backend.isRead('e-2'), isTrue);
    expect(find.byKey(const Key('unread')), findsNothing);
    expect(find.byKey(const Key('unreadCount')), findsNothing);
    final button = tester.widget<IconButton>(
      find.byKey(const Key('markAllRead')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('a failed mark all read says why', (tester) async {
    await connect(tester);
    backend.offline = true;

    await tester.tap(find.byKey(const Key('markAllRead')));
    await settle(tester);

    expect(find.text('Could not reach the server'), findsOneWidget);
    expect(unreadDot('Nightly build failed'), findsOneWidget);
  });

  testWidgets('shows why setup failed', (tester) async {
    backend.acceptedKey = null;

    await connect(tester);

    expect(
      find.text('The server did not accept this client key'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('connect')), findsOneWidget);
  });

  testWidgets('a push received while open shows up in the inbox', (
    tester,
  ) async {
    await connect(tester);
    backend.publish('e-2', 'Deploy done');

    push.received.add(
      const PushNotice(title: 'Deploy done', body: 'v1.2.3', eventId: 'e-2'),
    );
    await settle(tester);

    expect(find.text('Deploy done'), findsOneWidget);
  });

  testWidgets('returning to the app shows events pushed meanwhile', (
    tester,
  ) async {
    await connect(tester);
    backend.publish('e-2', 'Deploy done');

    // Home, then back: the states Android goes through.
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await settle(tester);

    expect(find.text('Deploy done'), findsOneWidget);
  });

  testWidgets('a tapped notification opens its event', (tester) async {
    await connect(tester);
    backend.publish('e-2', 'Deploy done', message: 'v1.2.3 is live.');

    push.received.add(
      const PushNotice(title: 'Deploy done', eventId: 'e-2', opened: true),
    );
    await settle(tester);

    expect(find.text('v1.2.3 is live.'), findsOneWidget);
    expect(find.text('e-2'), findsOneWidget);
    expect(backend.isRead('e-2'), isTrue);
  });

  testWidgets('a notification for an unknown event says so', (tester) async {
    await connect(tester);

    push.received.add(
      const PushNotice(title: 'Gone', eventId: 'e-404', opened: true),
    );
    await settle(tester);

    expect(
      find.text('This event does not exist on the server'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('retryEvent')), findsOneWidget);
  });

  testWidgets('disconnecting returns to setup', (tester) async {
    await connect(tester);

    await tester.tap(find.byType(PopupMenuButton<void>));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('disconnect')));
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('connect')), findsOneWidget);
    expect(backend.pushTarget, isNull);
  });

  Future<void> openNotifications(WidgetTester tester) async {
    // Tall enough to build every row of the list.
    tester.view
      ..physicalSize = const Size(800, 2000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.tap(find.byType(PopupMenuButton<void>));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notifications')));
    await tester.pumpAndSettle();
  }

  Future<void> tapAndSave(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await settle(tester);
  }

  testWidgets('sets which events are pushed to this device', (tester) async {
    backend.publish(
      'e-2',
      'Disk almost full',
      producer: {'id': 'p-2', 'name': 'nas-monitor'},
    );
    await connect(tester);
    await openNotifications(tester);

    expect(find.text('nightly-build'), findsOneWidget);
    expect(find.text('nas-monitor'), findsOneWidget);

    await tapAndSave(tester, find.text('High'));
    await tapAndSave(tester, find.byKey(const Key('category-INFO')));
    await tapAndSave(tester, find.byKey(const Key('producer-p-2')));

    expect(backend.pushPreferences, {
      'enabled': true,
      'minimumSeverity': 'HIGH',
      'mutedCategories': ['INFO'],
      'mutedProducerIds': ['p-2'],
    });
    final info = tester.widget<SwitchListTile>(
      find.byKey(const Key('category-INFO')),
    );
    expect(info.value, isFalse);

    await tapAndSave(tester, find.byKey(const Key('pushEnabled')));

    expect(backend.pushPreferences?['enabled'], isFalse);
    expect(
      find.text('Paused. Events are still kept in the inbox.'),
      findsOneWidget,
    );
    // Pausing keeps everything else.
    expect(backend.pushPreferences?['minimumSeverity'], 'HIGH');
  });

  testWidgets('a muted producer without inbox events can be unmuted', (
    tester,
  ) async {
    backend.pushPreferences = {
      ...FakeBackend.defaultPushPreferences,
      'mutedProducerIds': ['p-gone'],
    };
    await connect(tester);
    await openNotifications(tester);

    expect(find.text('p-gone'), findsOneWidget);
    await tapAndSave(tester, find.byKey(const Key('producer-p-gone')));

    expect(backend.pushPreferences?['mutedProducerIds'], isEmpty);
  });

  testWidgets('a failed change is reported and not shown', (tester) async {
    await connect(tester);
    await openNotifications(tester);
    backend.offline = true;

    await tapAndSave(tester, find.byKey(const Key('pushEnabled')));

    expect(find.text('Could not reach the server'), findsOneWidget);
    final enabled = tester.widget<SwitchListTile>(
      find.byKey(const Key('pushEnabled')),
    );
    expect(enabled.value, isTrue);
  });

  testWidgets('a server without push preferences says so', (tester) async {
    backend.pushPreferences = null;
    await connect(tester);
    await openNotifications(tester);

    expect(
      find.textContaining('does not support push preferences'),
      findsOneWidget,
    );
  });

  group('inbox filters', () {
    setUp(() {
      backend
        ..publish(
          'e-2',
          'Disk almost full',
          category: 'INFO',
          severity: 'NORMAL',
          producer: {'id': 'p-2', 'name': 'nas'},
        )
        ..publish('e-3', 'Deploy done', readAt: '2026-09-25T12:10:00Z');
    });

    Future<void> openFilters(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('filter')));
      await tester.pumpAndSettle();
    }

    Future<void> tapInSheet(WidgetTester tester, Finder target) async {
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await settle(tester);
    }

    Future<void> closeSheet(WidgetTester tester) async {
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    }

    testWidgets('show unread events only', (tester) async {
      await connect(tester);
      expect(find.text('Deploy done'), findsOneWidget);
      expect(find.byKey(const Key('activeFilters')), findsNothing);

      await openFilters(tester);
      await tapInSheet(tester, find.byKey(const Key('unreadOnly')));
      await closeSheet(tester);

      expect(find.text('Deploy done'), findsNothing);
      expect(find.text('Nightly build failed'), findsOneWidget);
      expect(find.text('Disk almost full'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('activeFilters')),
          matching: find.text('Unread'),
        ),
        findsOneWidget,
      );
      expect(
        backend.requests
            .lastWhere((r) => r.url.path == '/api/v1/events')
            .url
            .queryParameters['read'],
        'false',
      );
    });

    testWidgets('filter by producer, category and severity', (tester) async {
      await connect(tester);

      await openFilters(tester);
      await tapInSheet(tester, find.byKey(const Key('filterProducer-p-2')));
      await tapInSheet(tester, find.byKey(const Key('filterCategory-INFO')));
      await tapInSheet(tester, find.byKey(const Key('filterSeverity-NORMAL')));
      await closeSheet(tester);

      expect(find.text('Disk almost full'), findsOneWidget);
      expect(find.text('Nightly build failed'), findsNothing);
      final bar = find.byKey(const Key('activeFilters'));
      for (final label in ['nas', 'Info', 'Normal']) {
        expect(
          find.descendant(of: bar, matching: find.text(label)),
          findsOneWidget,
        );
      }
      // Marking read up to the newest event shown would mark hidden ones.
      final markAllRead = tester.widget<IconButton>(
        find.byKey(const Key('markAllRead')),
      );
      expect(markAllRead.onPressed, isNull);
    });

    testWidgets('clear every filter with one tap', (tester) async {
      await connect(tester);
      await openFilters(tester);
      await tapInSheet(tester, find.byKey(const Key('unreadOnly')));
      await tapInSheet(tester, find.byKey(const Key('filterProducer-p-2')));
      await closeSheet(tester);
      expect(find.text('Nightly build failed'), findsNothing);

      await tester.tap(find.byKey(const Key('clearFilters')));
      await settle(tester);

      expect(find.byKey(const Key('activeFilters')), findsNothing);
      for (final title in [
        'Nightly build failed',
        'Disk almost full',
        'Deploy done',
      ]) {
        expect(find.text(title), findsOneWidget);
      }
    });

    testWidgets('say when no event matches', (tester) async {
      await connect(tester);
      await openFilters(tester);
      await tapInSheet(
        tester,
        find.byKey(const Key('filterCategory-ACTION_REQUIRED')),
      );
      await closeSheet(tester);

      expect(find.text('No events match these filters'), findsOneWidget);
    });

    testWidgets('an older server\'s unread-only view reads on past pages of '
        'read events', (tester) async {
      backend.readFilter = false;
      for (var i = 0; i < AppController.pageSize; i++) {
        backend.publish('r-$i', 'Read $i', readAt: '2026-09-25T12:10:00Z');
      }
      await connect(tester);

      await openFilters(tester);
      await tapInSheet(tester, find.byKey(const Key('unreadOnly')));
      await closeSheet(tester);
      await settle(tester);

      expect(find.textContaining('Read '), findsNothing);
      expect(find.text('Nightly build failed'), findsOneWidget);
      expect(find.text('Disk almost full'), findsOneWidget);
    });
  });

  group('device management', () {
    const tablet = 'c-tablet';
    const laptop = 'c-laptop';

    setUp(() {
      backend
        ..admin = true
        ..addClient(tablet, 'Tablet')
        ..addClient(laptop, 'Laptop', admin: true)
        ..addClient('c-phone', 'Old phone');
      backend.otherClients.last['revokedAt'] = '2026-09-26T09:00:00Z';
    });

    Future<void> openDevices(WidgetTester tester) async {
      await connect(tester);
      await openDevice(tester);
      await settle(tester);
    }

    Finder inDevice(String id, Finder matching) =>
        find.descendant(of: find.byKey(Key('device-$id')), matching: matching);

    Future<void> choose(WidgetTester tester, String id, String action) async {
      await tester.ensureVisible(find.byKey(Key('deviceActions-$id')));
      await tester.tap(find.byKey(Key('deviceActions-$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key(action)));
      await tester.pumpAndSettle();
    }

    testWidgets('a device that is not an admin shows no devices', (
      tester,
    ) async {
      backend.admin = false;

      await openDevices(tester);

      expect(find.text('Devices'), findsNothing);
      expect(find.text('Tablet'), findsNothing);
      expect(find.byKey(const Key('connectDevice')), findsNothing);
      expect(
        backend.requests.where((r) => r.url.path.contains('/devices')),
        isEmpty,
      );
    });

    testWidgets('a server older than device management shows nothing', (
      tester,
    ) async {
      backend.deviceEndpoints = false;

      await openDevices(tester);

      expect(find.text('Devices'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text(AppController.notAdminMessage), findsNothing);
    });

    testWidgets('an admin device lists every device', (tester) async {
      await openDevices(tester);

      expect(find.text('Devices'), findsOneWidget);
      const self = '01a0da2c-1f3e-7a51-8d0c-6b1f2e3d4c5b';
      expect(
        inDevice(self, find.text('This device · Admin device')),
        findsOneWidget,
      );
      expect(inDevice(laptop, find.text('Admin device')), findsOneWidget);
      expect(inDevice(tablet, find.text('Tablet')), findsOneWidget);
      expect(inDevice('c-phone', find.text('Revoked')), findsOneWidget);
      // Admins, this device included, and revoked devices offer nothing.
      expect(find.byKey(const Key('deviceActions-$self')), findsNothing);
      expect(find.byKey(const Key('deviceActions-$laptop')), findsNothing);
      expect(find.byKey(const Key('deviceActions-c-phone')), findsNothing);
      expect(find.byKey(const Key('deviceActions-$tablet')), findsOneWidget);
    });

    testWidgets('revokes a device after a confirmation', (tester) async {
      await openDevices(tester);

      await choose(tester, tablet, 'revoke');
      expect(find.text('Revoke "Tablet"?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(backend.otherClients.first['revokedAt'], isNull);

      await choose(tester, tablet, 'revoke');
      await tester.tap(find.byKey(const Key('confirm')));
      await settle(tester);

      expect(backend.otherClients.first['revokedAt'], isNotNull);
      expect(inDevice(tablet, find.text('Revoked')), findsOneWidget);
      expect(find.byKey(const Key('deviceActions-$tablet')), findsNothing);
    });

    testWidgets('makes a device an admin after a confirmation', (tester) async {
      await openDevices(tester);

      await choose(tester, tablet, 'makeAdmin');
      expect(find.text('Make "Tablet" an admin device?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm')));
      await settle(tester);

      expect(backend.otherClients.first['admin'], isTrue);
      expect(inDevice(tablet, find.text('Admin device')), findsOneWidget);
      expect(find.byKey(const Key('deviceActions-$tablet')), findsNothing);
    });

    testWidgets('a refused change says why', (tester) async {
      await openDevices(tester);
      backend.otherClients.first['admin'] = true;

      await choose(tester, tablet, 'revoke');
      await tester.tap(find.byKey(const Key('confirm')));
      await settle(tester);

      expect(
        find.text('The server answered 409: Client is an admin device'),
        findsOneWidget,
      );
      expect(inDevice(tablet, find.text('Admin device')), findsOneWidget);
    });

    testWidgets('rights taken away meanwhile are explained', (tester) async {
      await openDevices(tester);
      backend.admin = false;

      await choose(tester, tablet, 'makeAdmin');
      await tester.tap(find.byKey(const Key('confirm')));
      await settle(tester);

      expect(backend.otherClients.first['admin'], isFalse);
      expect(
        find.descendant(
          of: find.byKey(const Key('notAdmin')),
          matching: find.text(AppController.notAdminMessage),
        ),
        findsOneWidget,
      );
      expect(find.text('Tablet'), findsNothing);
    });

    Future<void> createPairing(WidgetTester tester, String name) async {
      await tester.tap(find.byKey(const Key('connectDevice')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('pairingName')), name);
      await tester.tap(find.byKey(const Key('createPairing')));
      await settle(tester);
    }

    Future<void> goBack(WidgetTester tester) async {
      await tester.tap(find.byType(BackButton));
      await settle(tester);
    }

    testWidgets('an admin device connects a device with a QR code', (
      tester,
    ) async {
      backend.pairingExpiresAt = DateTime.now().add(
        const Duration(minutes: 10),
      );
      await openDevices(tester);

      await createPairing(tester, 'New tablet');

      expect(backend.devicePairingNames, ['New tablet']);
      expect(
        tester.widget<PairingQr>(find.byType(PairingQr)).data,
        controller.pairingLink,
      );
      expect(find.textContaining('It works once.'), findsOneWidget);
      expect(find.byKey(const Key('copyLink')), findsOneWidget);

      // Back on the devices, the code is forgotten and the list re-read.
      final listings = backend.requests
          .where((r) => r.url.path == '/api/v1/client/devices')
          .length;
      await goBack(tester);
      expect(controller.pairing, isNull);
      expect(
        backend.requests
            .where((r) => r.url.path == '/api/v1/client/devices')
            .length,
        listings + 1,
      );
    });

    testWidgets('a server older than pairing from a device says so', (
      tester,
    ) async {
      backend.devicePairings = false;
      await openDevices(tester);

      await createPairing(tester, 'New tablet');

      expect(
        find.text(AppController.pairingUnsupportedMessage),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('createPairing')))
            .onPressed,
        isNull,
      );
      await goBack(tester);
      // Device management stays; connecting a device is no longer offered.
      expect(find.byKey(const Key('connectDevice')), findsNothing);
      expect(inDevice(tablet, find.text('Tablet')), findsOneWidget);
    });

    testWidgets('rights taken away before creating a code are explained', (
      tester,
    ) async {
      await openDevices(tester);
      backend.admin = false;

      await createPairing(tester, 'New tablet');

      expect(find.text(AppController.notAdminMessage), findsOneWidget);
      expect(find.byType(PairingQr), findsNothing);
      expect(backend.devicePairingNames, isEmpty);
      await goBack(tester);
      expect(find.byKey(const Key('notAdmin')), findsOneWidget);
      expect(find.byKey(const Key('connectDevice')), findsNothing);
    });
  });
}
