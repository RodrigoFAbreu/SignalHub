import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/alert/alert_settings.dart';
import 'package:signalhub_client/src/api/signalhub_api.dart';
import 'package:signalhub_client/src/app.dart';
import 'package:signalhub_client/src/app_controller.dart';
import 'package:signalhub_client/src/build_identity.dart';
import 'package:signalhub_client/src/connection/pairing_uri.dart';
import 'package:signalhub_client/src/push/push_registration.dart';
import 'package:signalhub_client/src/push/push_service.dart';
import 'package:signalhub_client/src/ui/connect_device_screen.dart';
import 'package:signalhub_client/src/settings/settings_groups.dart';
import 'package:signalhub_client/src/ui/devices_screen.dart';
import 'package:signalhub_client/src/ui/event_screen.dart';

import 'support/fakes.dart';
import 'support/phone.dart';

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
    await tester.scrollUntilVisible(
      find.byKey(const Key('connect')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
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

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('tab-settings')));
    await tester.pumpAndSettle();
  }

  /// Opens or folds [group] of the Settings screen by its header.
  Future<void> toggleGroup(WidgetTester tester, SettingsGroup group) async {
    final header = find.byKey(Key('summary-${group.name}'));
    await tester.ensureVisible(header);
    await tester.pumpAndSettle();
    await tester.tap(header);
    await tester.pumpAndSettle();
  }

  Future<void> openDevice(WidgetTester tester) async {
    await openSettings(tester);
    await toggleGroup(tester, SettingsGroup.device);
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

  testWidgets('a long event scrolls clear of the navigation bar', (
    tester,
  ) async {
    useEdgeToEdgePhone(tester);
    backend.publish(
      'e-2',
      'Deploy done',
      message: List.filled(60, 'A line of the message.').join('\n'),
    );
    await connect(tester);
    await tester.tap(find.text('Deploy done'));
    await tester.pumpAndSettle();

    await scrollToEnd(tester, find.byType(EventScreen));

    expectClearOfNavigationBar(tester, find.byKey(const Key('metadata')));
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

  testWidgets('disconnecting from Settings returns to setup after a '
      'confirmation', (tester) async {
    await connect(tester);
    await openDevice(tester);

    await tester.tap(find.byKey(const Key('disconnect')));
    await tester.pumpAndSettle();
    expect(find.text('Disconnect this device?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(find.byKey(const Key('disconnect')), findsOneWidget);
    expect(backend.pushTarget, isNotNull);

    await tester.tap(find.byKey(const Key('disconnect')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm')));
    await settle(tester);

    expect(find.byKey(const Key('scanPairing')), findsOneWidget);
    expect(find.byKey(const Key('tab-settings')), findsNothing);
    expect(backend.pushTarget, isNull);
  });

  /// Opens Settings with the push filters and, where there are alert
  /// settings, both alert groups unfolded.
  Future<void> openNotifications(WidgetTester tester) async {
    // Tall enough to build every row of the list.
    tester.view
      ..physicalSize = const Size(800, 6000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await openSettings(tester);
    await toggleGroup(tester, SettingsGroup.pushFilters);
    if (controller.alert case final alert?) {
      await toggleGroup(tester, SettingsGroup.alert);
      // The critical alert's own settings, once critical events have one.
      if (alert.critical.different) {
        await toggleGroup(tester, SettingsGroup.critical);
      }
    }
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

  group('alert', () {
    late FakeAlertPlatform alerts;

    setUp(() {
      alerts = FakeAlertPlatform();
      // A notice stream is listened to once, so a push service of its own.
      push = FakePushService();
      controller = AppController(
        store: InMemoryCredentialsStore(),
        apiFactory: (credentials) =>
            backend.api(credentials.baseUrl, credentials.clientKey),
        redeemPairing: backend.redeemPairing,
        push: push,
        alertPlatform: alerts,
      );
    });

    AlertSettings stored() => AlertSettings.fromStored(alerts.stored)!;
    CriticalAlertSettings storedCritical() =>
        CriticalAlertSettings.fromStored(alerts.stored)!;
    QuietModeSettings storedQuiet() =>
        QuietModeSettings.fromStored(alerts.stored)!;
    bool switchValue(WidgetTester tester, String key) =>
        tester.widget<SwitchListTile>(find.byKey(Key(key))).value;
    Set<SoundThrough> quietChoice(WidgetTester tester, String key) => tester
        .widget<SegmentedButton<SoundThrough>>(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(SegmentedButton<SoundThrough>),
          ),
        )
        .selected;
    Future<void> chooseQuiet(
      WidgetTester tester,
      String key,
      String option,
    ) async {
      final target = find.descendant(
        of: find.byKey(Key(key)),
        matching: find.text(option),
      );
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tapAndSave(tester, target);
    }

    Future<void> tapCritical(WidgetTester tester, String key) async {
      final target = find.byKey(Key(key));
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tapAndSave(tester, target);
    }

    testWidgets('by default critical events play the general alert and '
        'sound on silent only', (tester) async {
      await connect(tester);
      await openNotifications(tester);

      expect(switchValue(tester, 'criticalDifferent'), isFalse);
      expect(find.byKey(const Key('criticalSound-urgent')), findsNothing);
      expect(quietChoice(tester, 'soundOnSilent'), {SoundThrough.critical});
      expect(quietChoice(tester, 'soundDuringDoNotDisturb'), {
        SoundThrough.off,
      });
      expect(storedCritical(), CriticalAlertSettings.defaults);
      expect(storedQuiet(), QuietModeSettings.defaults);
    });

    testWidgets('critical events get a different alert of their own', (
      tester,
    ) async {
      await connect(tester);
      await openNotifications(tester);

      await tapCritical(tester, 'criticalDifferent');
      expect(storedCritical().different, isTrue);
      expect(alerts.previewed, isEmpty);
      await toggleGroup(tester, SettingsGroup.critical);
      expect(find.text('Urgent (default)'), findsOneWidget);

      await tapCritical(tester, 'criticalSound-glass');
      expect(storedCritical().alert.sound, AlertSound.glass);
      expect(alerts.previewed.last['resource'], 'signalhub_glass');
      expect(alerts.previewed.last['onSilent'], isTrue);

      await tapCritical(tester, 'criticalPlay-pulse');
      expect(alerts.previewed.last['resource'], 'signalhub_pulse');
      expect(storedCritical().alert.sound, AlertSound.glass);

      final light = find.descendant(
        of: find.byKey(const Key('criticalVibration')),
        matching: find.text('Light'),
      );
      await tester.ensureVisible(light);
      await tapAndSave(tester, light);
      expect(storedCritical().alert.vibration, AlertVibration.light);

      // Every other push keeps the general alert.
      expect(stored(), AlertSettings.defaults);
      expect(alerts.saved.last['resource'], 'signalhub_signal');
      expect(
        (alerts.saved.last['criticalAlert']! as Map)['resource'],
        'signalhub_glass',
      );

      await tapCritical(tester, 'criticalDifferent');
      expect(find.byKey(const Key('criticalSound-glass')), findsNothing);
      expect(
        (alerts.saved.last['criticalAlert']! as Map)['resource'],
        'signalhub_signal',
      );
      // Kept for when the switch is on again.
      expect(storedCritical().alert.sound, AlertSound.glass);
    });

    testWidgets('chooses which pushes sound on silent', (tester) async {
      await connect(tester);
      await openNotifications(tester);

      await chooseQuiet(tester, 'soundOnSilent', 'All pushes');
      expect(quietChoice(tester, 'soundOnSilent'), {SoundThrough.all});
      expect(storedQuiet().onSilent, SoundThrough.all);
      expect(alerts.saved.last['onSilent'], isTrue);
      expect((alerts.saved.last['criticalAlert']! as Map)['onSilent'], isTrue);

      await chooseQuiet(tester, 'soundOnSilent', 'Off');
      expect(storedQuiet().onSilent, SoundThrough.off);
      expect(alerts.saved.last['onSilent'], isFalse);
      expect((alerts.saved.last['criticalAlert']! as Map)['onSilent'], isFalse);

      await chooseQuiet(tester, 'soundOnSilent', 'Critical only');
      expect(storedQuiet().onSilent, SoundThrough.critical);
      expect(alerts.saved.last['onSilent'], isFalse);
      expect((alerts.saved.last['criticalAlert']! as Map)['onSilent'], isTrue);
      // Nothing is previewed, and the critical settings are their own.
      expect(alerts.previewed, isEmpty);
      expect(storedCritical(), CriticalAlertSettings.defaults);
    });

    testWidgets('sounding during Do Not Disturb asks for the access first', (
      tester,
    ) async {
      await connect(tester);
      await openNotifications(tester);
      expect(find.textContaining('Needs Do Not Disturb access'), findsOne);

      await chooseQuiet(tester, 'soundDuringDoNotDisturb', 'Critical only');

      expect(alerts.accessOpened, 1);
      expect(
        find.textContaining('Allow SignalHub in Do Not Disturb'),
        findsOne,
      );
      expect(quietChoice(tester, 'soundDuringDoNotDisturb'), {
        SoundThrough.off,
      });
      expect(storedQuiet().duringDoNotDisturb, SoundThrough.off);

      // The owner gives it in the phone's settings and comes back.
      alerts.access = true;
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(find.textContaining('Needs Do Not Disturb access'), findsNothing);
      expect(quietChoice(tester, 'soundDuringDoNotDisturb'), {
        SoundThrough.off,
      });

      await chooseQuiet(tester, 'soundDuringDoNotDisturb', 'All pushes');

      expect(quietChoice(tester, 'soundDuringDoNotDisturb'), {
        SoundThrough.all,
      });
      expect(storedQuiet().duringDoNotDisturb, SoundThrough.all);
      expect(alerts.saved.last['duringDoNotDisturb'], isTrue);
      expect(alerts.accessOpened, 1);
    });

    testWidgets('sets the sound, volume and vibration, each previewed', (
      tester,
    ) async {
      await connect(tester);
      await openNotifications(tester);

      expect(find.text('Alert'), findsOneWidget);
      expect(find.text('Signal (default)'), findsOneWidget);

      await tapAndSave(tester, find.byKey(const Key('alertSound-beacon')));
      expect(stored().sound, AlertSound.beacon);
      expect(alerts.previewed.last['resource'], 'signalhub_beacon');
      expect(alerts.previewed.last['timings'], isEmpty);

      // The slider runs from 10 % at its left end to 100 % at its right.
      final slider = find.byKey(const Key('alertVolume'));
      await tester.drag(slider, Offset(-tester.getSize(slider).width, 0));
      await settle(tester);
      expect(stored().volume, AlertSettings.minVolume);
      expect(alerts.previewed.last['gain'], 0.1);

      await tapAndSave(tester, find.text('Strong'));
      expect(stored().vibration, AlertVibration.strong);
      expect(alerts.previewed.last['resource'], isNull);
      expect(alerts.previewed.last['amplitudes'], contains(255));

      // Nothing of it reaches the server.
      expect(
        backend.requests.where((r) => r.url.path.contains('alert')),
        isEmpty,
      );
    });

    testWidgets('sets the vibration\'s pattern and length, each previewed', (
      tester,
    ) async {
      await connect(tester);
      await openNotifications(tester);

      final heartbeat = find.byKey(const Key('alertPattern-heartbeat'));
      await tester.ensureVisible(heartbeat);
      await tester.pumpAndSettle();
      await tapAndSave(tester, heartbeat);
      expect(stored().pattern, AlertPattern.heartbeat);
      expect(alerts.previewed.last['resource'], isNull);
      expect(alerts.previewed.last['timings'], [0, 80, 120, 200]);

      final long = find.descendant(
        of: find.byKey(const Key('alertLength')),
        matching: find.text('Long'),
      );
      await tester.ensureVisible(long);
      await tester.pumpAndSettle();
      await tapAndSave(tester, long);
      expect(stored().length, AlertLength.long);
      expect(alerts.previewed.last['pattern'], 'heartbeat');
      expect(alerts.previewed.last['length'], 'long');
      expect(alerts.saved.last['timings'], hasLength(24));

      // A pattern felt again without choosing it, at the chosen length.
      await tapAndSave(tester, find.byTooltip('Vibrate Rapid pulse'));
      expect(alerts.previewed.last['pattern'], 'rapid');
      expect(alerts.previewed.last['length'], 'long');
      expect(stored().pattern, AlertPattern.heartbeat);

      // The intensity still applies to the chosen pattern and length.
      await tapAndSave(tester, find.text('Strong'));
      expect(stored().pattern, AlertPattern.heartbeat);
      expect(alerts.previewed.last['amplitudes'], contains(255));
      expect(alerts.previewed.last['length'], 'long');
    });

    testWidgets('the pattern and length are greyed while the vibration is '
        'off', (tester) async {
      await connect(tester);
      await openNotifications(tester);

      final off = find.descendant(
        of: find.byKey(const Key('alertVibration')),
        matching: find.text('Off'),
      );
      await tapAndSave(tester, off);

      final pattern = tester.widget<RadioListTile<AlertPattern>>(
        find.byKey(const Key('alertPattern-steady')),
      );
      expect(pattern.enabled, isFalse);
      final length = tester.widget<SegmentedButton<AlertLength>>(
        find.byKey(const Key('alertLength')),
      );
      expect(length.segments.every((s) => !s.enabled), isTrue);
    });

    testWidgets('critical events get a pattern and length of their own', (
      tester,
    ) async {
      await connect(tester);
      await openNotifications(tester);
      expect(find.byKey(const Key('criticalPattern-rapid')), findsNothing);

      await tapCritical(tester, 'criticalDifferent');
      await toggleGroup(tester, SettingsGroup.critical);
      final rapid = tester.widget<RadioListTile<AlertPattern>>(
        find.byKey(const Key('criticalPattern-rapid')),
      );
      expect(
        RadioGroup.maybeOf<AlertPattern>(
          tester.element(find.byKey(const Key('criticalPattern-rapid'))),
        )?.groupValue,
        rapid.value,
      );
      expect(
        tester
            .widget<SegmentedButton<AlertLength>>(
              find.byKey(const Key('criticalLength')),
            )
            .selected,
        {AlertLength.long},
      );

      await tapCritical(tester, 'criticalPattern-steady');
      expect(storedCritical().alert.pattern, AlertPattern.steady);
      expect(alerts.previewed.last['timings'], [0, 5000]);
      expect(alerts.previewed.last['onSilent'], isTrue);

      final medium = find.descendant(
        of: find.byKey(const Key('criticalLength')),
        matching: find.text('Medium'),
      );
      await tester.ensureVisible(medium);
      await tapAndSave(tester, medium);
      expect(storedCritical().alert.length, AlertLength.medium);
      expect((alerts.saved.last['criticalAlert']! as Map)['timings'], [
        0,
        2000,
      ]);

      // Every other push keeps the general alert's.
      expect(stored(), AlertSettings.defaults);
      expect(alerts.saved.last['timings'], [0, 90, 90, 90, 90, 260]);
    });

    testWidgets('a sound is played again without choosing it', (tester) async {
      await connect(tester);
      await openNotifications(tester);

      await tapAndSave(tester, find.byTooltip('Play Glass'));

      expect(alerts.previewed.single['resource'], 'signalhub_glass');
      expect(stored().sound, AlertSound.signal);
    });

    testWidgets('no sound turns the volume off', (tester) async {
      await connect(tester);
      await openNotifications(tester);

      await tapAndSave(tester, find.byKey(const Key('alertSound-none')));

      expect(stored().sound, isNull);
      final slider = tester.widget<Slider>(
        find.byKey(const Key('alertVolume')),
      );
      expect(slider.onChanged, isNull);
    });

    testWidgets('the saved settings are shown after a restart', (tester) async {
      alerts.stored = jsonEncode(
        platformAlerts(
          const AlertSettings(
            sound: AlertSound.pulse,
            volume: 30,
            vibration: AlertVibration.off,
            pattern: AlertPattern.heartbeat,
            length: AlertLength.medium,
          ),
          CriticalAlertSettings.defaults.copyWith(different: true),
          const QuietModeSettings(
            onSilent: SoundThrough.off,
            duringDoNotDisturb: SoundThrough.critical,
          ),
        ),
      );
      await connect(tester);
      await openNotifications(tester);

      final pulse = tester.widget<RadioListTile<String>>(
        find.byKey(const Key('alertSound-pulse')),
      );
      expect(
        RadioGroup.maybeOf<String>(
          tester.element(find.byKey(const Key('alertSound-pulse'))),
        )?.groupValue,
        pulse.value,
      );
      expect(
        tester.widget<Slider>(find.byKey(const Key('alertVolume'))).value,
        30,
      );
      final vibration = tester.widget<SegmentedButton<AlertVibration>>(
        find.byKey(const Key('alertVibration')),
      );
      expect(vibration.selected, {AlertVibration.off});
      expect(
        tester
            .widget<SegmentedButton<AlertLength>>(
              find.byKey(const Key('alertLength')),
            )
            .selected,
        {AlertLength.medium},
      );
      expect(
        tester.widget<Slider>(find.byKey(const Key('criticalVolume'))).value,
        100,
      );
      expect(switchValue(tester, 'criticalDifferent'), isTrue);
      expect(quietChoice(tester, 'soundOnSilent'), {SoundThrough.off});
      // Shown Off without Do Not Disturb access, and kept as chosen.
      expect(quietChoice(tester, 'soundDuringDoNotDisturb'), {
        SoundThrough.off,
      });
      expect(alerts.saved, isEmpty);
    });

    testWidgets('says when the phone keeps a preview quiet', (tester) async {
      alerts.plays = false;
      await connect(tester);
      await openNotifications(tester);

      await tapAndSave(tester, find.byKey(const Key('alertSound-glass')));

      expect(find.textContaining('Silent mode or Do Not Disturb'), findsOne);
      expect(stored().sound, AlertSound.glass);
    });

    testWidgets('is set on a server without push preferences', (tester) async {
      backend.pushPreferences = null;
      await connect(tester);
      await openNotifications(tester);

      expect(find.text('Alert'), findsOneWidget);
      expect(
        find.textContaining('does not support push preferences'),
        findsOneWidget,
      );
    });

    testWidgets('stays when the device disconnects', (tester) async {
      await connect(tester);
      await openNotifications(tester);
      await tapAndSave(tester, find.byKey(const Key('alertSound-pulse')));
      await toggleGroup(tester, SettingsGroup.device);

      await tester.tap(find.byKey(const Key('disconnect')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm')));
      await settle(tester);

      expect(stored().sound, AlertSound.pulse);
    });
  });

  testWidgets('without an alert platform there are no alert settings', (
    tester,
  ) async {
    await connect(tester);
    await openNotifications(tester);

    expect(find.text('Alert'), findsNothing);
    expect(find.byKey(const Key('pushEnabled')), findsOneWidget);
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

    testWidgets('an event read from the unread-only view leaves it', (
      tester,
    ) async {
      await connect(tester);
      await openFilters(tester);
      await tapInSheet(tester, find.byKey(const Key('unreadOnly')));
      await closeSheet(tester);

      await tester.tap(find.text('Nightly build failed'));
      await settle(tester);
      // Its own screen keeps showing it, as read.
      expect(find.byKey(const Key('markUnread')), findsOneWidget);
      await tester.pageBack();
      await settle(tester);

      expect(find.text('Nightly build failed'), findsNothing);
      expect(find.text('Disk almost full'), findsOneWidget);
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

  group('settings', () {
    late FakeAlertPlatform alerts;
    late InMemoryOpenGroupsStore openGroups;

    setUp(() {
      alerts = FakeAlertPlatform();
      openGroups = InMemoryOpenGroupsStore();
      push = FakePushService();
      controller = AppController(
        store: InMemoryCredentialsStore(),
        apiFactory: (credentials) =>
            backend.api(credentials.baseUrl, credentials.clientKey),
        redeemPairing: backend.redeemPairing,
        push: push,
        alertPlatform: alerts,
        openGroups: openGroups,
      );
    });

    String summary(WidgetTester tester, SettingsGroup group) =>
        tester.widget<Text>(find.byKey(Key('summary-${group.name}'))).data!;

    /// A setting of each group, shown only while the group is open.
    const insideGroup = {
      SettingsGroup.pushFilters: Key('minimumSeverity'),
      SettingsGroup.alert: Key('alertSound-signal'),
      SettingsGroup.critical: Key('criticalSound-urgent'),
      SettingsGroup.device: Key('disconnect'),
    };

    void expectOpen(Set<SettingsGroup> open) {
      for (final MapEntry(key: group, value: key) in insideGroup.entries) {
        expect(
          find.byKey(key),
          open.contains(group) ? findsOneWidget : findsNothing,
          reason: group.name,
        );
      }
    }

    void useTallView(WidgetTester tester) {
      tester.view
        ..physicalSize = const Size(800, 6000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('the Settings tab opens Settings with every group folded', (
      tester,
    ) async {
      await connect(tester);

      // No gear in the inbox: Settings is a tab of the bottom bar.
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
      await openSettings(tester);

      expect(find.widgetWithText(AppBar, 'Settings'), findsOneWidget);
      expect(find.byKey(const Key('pushEnabled')), findsOneWidget);
      for (final title in ['Push filters', 'Alert', 'This device']) {
        expect(find.text(title), findsOneWidget);
      }
      // Inside Alert, no longer a group of its own.
      expect(find.text('Critical alert'), findsNothing);
      expectOpen({});
    });

    testWidgets('each group unfolds to its settings and folds again', (
      tester,
    ) async {
      useTallView(tester);
      await connect(tester);
      await openSettings(tester);

      for (final group in SettingsGroup.values) {
        if (group == SettingsGroup.critical) continue;
        await toggleGroup(tester, group);
        expectOpen({group});
        await toggleGroup(tester, group);
        expectOpen({});
      }
    });

    ExpansionTile criticalGroup(WidgetTester tester) =>
        tester.widget<ExpansionTile>(find.byKey(const Key('group-critical')));

    testWidgets('the Critical alert sub-group is greyed and cannot be opened '
        'while critical events have no alert of their own', (tester) async {
      useTallView(tester);
      await connect(tester);
      await openSettings(tester);
      await toggleGroup(tester, SettingsGroup.alert);

      // Below the general alert, its two choices and the switch.
      final top = tester.getTopLeft(find.byKey(const Key('group-critical')));
      for (final key in [
        'alertLength',
        'soundOnSilent',
        'soundDuringDoNotDisturb',
        'criticalDifferent',
      ]) {
        expect(tester.getTopLeft(find.byKey(Key(key))).dy, lessThan(top.dy));
      }
      expect(criticalGroup(tester).enabled, isFalse);
      expect(summary(tester, SettingsGroup.critical), 'Same as Alert');
      final title = tester.renderObject<RenderParagraph>(
        find.text('Critical alert'),
      );
      expect(
        title.text.style?.color,
        Theme.of(tester.element(find.text('Critical alert'))).disabledColor,
      );

      await toggleGroup(tester, SettingsGroup.critical);

      expectOpen({SettingsGroup.alert});
      expect(openGroups.saved, {SettingsGroup.alert});
    });

    testWidgets('the Critical alert sub-group unfolds once the switch is on, '
        'and folds when it is turned off', (tester) async {
      useTallView(tester);
      await connect(tester);
      await openSettings(tester);
      await toggleGroup(tester, SettingsGroup.alert);

      await tapAndSave(tester, find.byKey(const Key('criticalDifferent')));
      expect(criticalGroup(tester).enabled, isTrue);
      expect(
        summary(tester, SettingsGroup.critical),
        'Urgent · 100 % · Strong · Rapid pulse · Long',
      );
      expectOpen({SettingsGroup.alert});

      await toggleGroup(tester, SettingsGroup.critical);
      expectOpen({SettingsGroup.alert, SettingsGroup.critical});
      await toggleGroup(tester, SettingsGroup.critical);
      expectOpen({SettingsGroup.alert});
      await toggleGroup(tester, SettingsGroup.critical);

      await tapAndSave(tester, find.byKey(const Key('criticalDifferent')));
      expect(criticalGroup(tester).enabled, isFalse);
      expectOpen({SettingsGroup.alert});

      // Left open, it opens again with the switch.
      await tapAndSave(tester, find.byKey(const Key('criticalDifferent')));
      expectOpen({SettingsGroup.alert, SettingsGroup.critical});
    });

    testWidgets('folded groups sum up the default settings', (tester) async {
      await connect(tester);
      await openSettings(tester);

      expect(
        summary(tester, SettingsGroup.pushFilters),
        'All severities · all categories · all producers',
      );
      expect(
        summary(tester, SettingsGroup.alert),
        'Signal · 80 % · Medium · Short, short, long · Short · sounds on '
        'silent: critical',
      );
      expect(
        summary(tester, SettingsGroup.device),
        'Pixel 8 · Push notifications are on',
      );
    });

    testWidgets('folded groups sum up settings changed from the defaults', (
      tester,
    ) async {
      backend
        ..publish(
          'e-2',
          'Disk almost full',
          producer: {'id': 'p-2', 'name': 'nas-monitor'},
        )
        ..pushPreferences = {
          ...FakeBackend.defaultPushPreferences,
          'minimumSeverity': 'NORMAL',
          'mutedCategories': ['INFO', 'COMPLETED'],
          'mutedProducerIds': ['p-2'],
        };
      alerts
        ..access = true
        ..stored = jsonEncode(
          platformAlerts(
            const AlertSettings(
              sound: AlertSound.pulse,
              volume: 30,
              vibration: AlertVibration.off,
            ),
            CriticalAlertSettings.defaults.copyWith(different: true),
            const QuietModeSettings(
              onSilent: SoundThrough.all,
              duringDoNotDisturb: SoundThrough.critical,
            ),
          ),
        );
      await connect(tester);
      await openSettings(tester);

      expect(
        summary(tester, SettingsGroup.pushFilters),
        'Normal and up · Completed, Info muted · nas-monitor muted',
      );
      expect(
        summary(tester, SettingsGroup.alert),
        'Pulse · 30 % · No vibration · sounds on silent: all pushes · during '
        'Do Not Disturb: critical',
      );
      await toggleGroup(tester, SettingsGroup.alert);
      expect(
        summary(tester, SettingsGroup.critical),
        'Urgent · 100 % · Strong · Rapid pulse · Long',
      );
    });

    testWidgets('a summary follows a change made in its group', (tester) async {
      useTallView(tester);
      await connect(tester);
      await openSettings(tester);
      await toggleGroup(tester, SettingsGroup.alert);

      await tapAndSave(tester, find.byKey(const Key('alertSound-beacon')));
      await tapAndSave(tester, find.text('Strong'));

      expect(
        summary(tester, SettingsGroup.alert),
        'Beacon · 80 % · Strong · Short, short, long · Short · sounds on '
        'silent: critical',
      );

      await tapAndSave(
        tester,
        find.descendant(
          of: find.byKey(const Key('soundOnSilent')),
          matching: find.text('Off'),
        ),
      );
      expect(
        summary(tester, SettingsGroup.alert),
        'Beacon · 80 % · Strong · Short, short, long · Short',
      );
    });

    testWidgets('the groups left open are open the next time', (tester) async {
      useTallView(tester);
      await connect(tester);
      await openSettings(tester);

      await toggleGroup(tester, SettingsGroup.alert);
      await toggleGroup(tester, SettingsGroup.device);
      await toggleGroup(tester, SettingsGroup.pushFilters);
      await toggleGroup(tester, SettingsGroup.pushFilters);
      expect(openGroups.saved, {SettingsGroup.alert, SettingsGroup.device});

      await tester.tap(find.byKey(const Key('tab-inbox')));
      await tester.pumpAndSettle();
      await openSettings(tester);

      expectOpen({SettingsGroup.alert, SettingsGroup.device});
    });

    testWidgets('the groups left open are read from the device at start', (
      tester,
    ) async {
      useTallView(tester);
      openGroups.saved = {SettingsGroup.alert, SettingsGroup.critical};
      alerts.stored = jsonEncode(
        platformAlerts(
          AlertSettings.defaults,
          CriticalAlertSettings.defaults.copyWith(different: true),
          QuietModeSettings.defaults,
        ),
      );
      await connect(tester);

      await openSettings(tester);

      expectOpen({SettingsGroup.alert, SettingsGroup.critical});
    });

    testWidgets('groups whose state cannot be kept still fold', (tester) async {
      useTallView(tester);
      openGroups.fails = true;
      await connect(tester);
      await openSettings(tester);

      await toggleGroup(tester, SettingsGroup.alert);

      expectOpen({SettingsGroup.alert});
    });

    testWidgets('while push is off, the groups it shapes are greyed and can '
        'still be changed', (tester) async {
      useTallView(tester);
      backend.pushPreferences = {
        ...FakeBackend.defaultPushPreferences,
        'enabled': false,
      };
      await connect(tester);
      await openSettings(tester);

      const note = 'Applies once push notifications are on';
      for (final group in [SettingsGroup.pushFilters, SettingsGroup.alert]) {
        expect(find.byKey(Key('pushOff-${group.name}')), findsOneWidget);
      }
      expect(find.text(note), findsNWidgets(2));
      expect(find.byKey(const Key('pushOff-device')), findsNothing);

      await toggleGroup(tester, SettingsGroup.pushFilters);
      await tapAndSave(tester, find.text('High'));
      expect(backend.pushPreferences?['minimumSeverity'], 'HIGH');
      expect(backend.pushPreferences?['enabled'], isFalse);
      await toggleGroup(tester, SettingsGroup.alert);
      await tapAndSave(tester, find.byKey(const Key('alertSound-glass')));
      expect(AlertSettings.fromStored(alerts.stored)!.sound, AlertSound.glass);

      await tapAndSave(tester, find.byKey(const Key('pushEnabled')));

      expect(find.text(note), findsNothing);
    });

    testWidgets('an admin device has a Devices row that opens its devices', (
      tester,
    ) async {
      backend
        ..admin = true
        ..addClient('c-tablet', 'Tablet')
        ..addClient('c-laptop', 'Laptop', admin: true)
        ..addClient('c-old', 'Old laptop', admin: true);
      // A revoked admin is no longer counted as one.
      backend.otherClients.last['revokedAt'] = '2026-09-26T09:00:00Z';
      await connect(tester);
      await openSettings(tester);
      await settle(tester);

      final row = find.byKey(const Key('devices'));
      expect(
        find.descendant(of: row, matching: find.text('4 devices · 2 admins')),
        findsOneWidget,
      );
      await tester.tap(row);
      await settle(tester);

      expect(find.text('Devices'), findsOneWidget);
      expect(find.text('Tablet'), findsOneWidget);
      expect(find.byKey(const Key('connectDevice')), findsOneWidget);
    });

    testWidgets('a device that is not an admin has no Devices row', (
      tester,
    ) async {
      await connect(tester);
      await openSettings(tester);
      await settle(tester);

      expect(find.byKey(const Key('devices')), findsNothing);
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
      await openSettings(tester);
      await settle(tester);
      await tester.tap(find.byKey(const Key('devices')));
      await settle(tester);
    }

    Finder inDevice(String id, Finder matching) =>
        find.descendant(of: find.byKey(Key('device-$id')), matching: matching);

    Future<void> openActions(WidgetTester tester, String id) async {
      await tester.ensureVisible(find.byKey(Key('deviceActions-$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('deviceActions-$id')));
      await tester.pumpAndSettle();
    }

    Future<void> choose(WidgetTester tester, String id, String action) async {
      await openActions(tester, id);
      await tester.tap(find.byKey(Key(action)));
      await tester.pumpAndSettle();
    }

    testWidgets('a device that is not an admin shows no devices', (
      tester,
    ) async {
      backend.admin = false;

      await connect(tester);
      await openSettings(tester);
      await settle(tester);

      expect(find.byKey(const Key('devices')), findsNothing);
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

      await connect(tester);
      await openSettings(tester);
      await settle(tester);

      expect(find.byKey(const Key('devices')), findsNothing);
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
      // Active admins, this device included, offer nothing.
      expect(find.byKey(const Key('deviceActions-$self')), findsNothing);
      expect(find.byKey(const Key('deviceActions-$laptop')), findsNothing);
      expect(find.byKey(const Key('deviceActions-$tablet')), findsOneWidget);
      expect(find.byKey(const Key('deviceActions-c-phone')), findsOneWidget);
    });

    testWidgets('only revoked devices offer to delete', (tester) async {
      await openDevices(tester);

      await openActions(tester, tablet);
      expect(find.byKey(const Key('revoke')), findsOneWidget);
      expect(find.byKey(const Key('delete')), findsNothing);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      await openActions(tester, 'c-phone');
      expect(find.byKey(const Key('delete')), findsOneWidget);
      expect(find.byKey(const Key('revoke')), findsNothing);
      expect(find.byKey(const Key('revoke')), findsNothing);
    });

    testWidgets('deletes a revoked device after a confirmation', (
      tester,
    ) async {
      await openDevices(tester);

      await choose(tester, 'c-phone', 'delete');
      expect(find.text('Delete "Old phone"?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(backend.otherClients.map((c) => c['id']), contains('c-phone'));

      await choose(tester, 'c-phone', 'delete');
      await tester.tap(find.byKey(const Key('confirm')));
      await settle(tester);

      expect(
        backend.otherClients.map((c) => c['id']),
        isNot(contains('c-phone')),
      );
      expect(find.byKey(const Key('device-c-phone')), findsNothing);
      expect(find.text('Old phone'), findsNothing);
    });

    testWidgets('a server older than deleting devices says so', (tester) async {
      backend.noDeviceDeletion = 404;
      await openDevices(tester);

      await choose(tester, 'c-phone', 'delete');
      await tester.tap(find.byKey(const Key('confirm')));
      await settle(tester);

      expect(
        find.text(AppController.deletingUnsupportedMessage),
        findsOneWidget,
      );
      expect(find.byKey(const Key('device-c-phone')), findsOneWidget);
      // Delete is not offered again; the other actions still are.
      expect(find.byKey(const Key('deviceActions-c-phone')), findsNothing);
      expect(find.byKey(const Key('deviceActions-$tablet')), findsOneWidget);
    });

    testWidgets('rights taken away before deleting are explained', (
      tester,
    ) async {
      await openDevices(tester);
      backend.admin = false;

      await choose(tester, 'c-phone', 'delete');
      await tester.tap(find.byKey(const Key('confirm')));
      await settle(tester);

      expect(backend.otherClients.map((c) => c['id']), contains('c-phone'));
      expect(find.byKey(const Key('notAdmin')), findsOneWidget);
      expect(find.text('Old phone'), findsNothing);
    });

    testWidgets('the last device scrolls clear of the navigation bar', (
      tester,
    ) async {
      useEdgeToEdgePhone(tester);
      // More devices than fit on the screen. Revoked ones come last and
      // offer no actions: the last device here is one that does.
      backend.otherClients.removeWhere((c) => c['revokedAt'] != null);
      for (var i = 1; i <= 20; i++) {
        backend.addClient('c-$i', 'Device $i');
      }
      await openDevices(tester);

      await scrollToEnd(tester, find.byType(DevicesScreen));

      expectClearOfNavigationBar(tester, find.byKey(const Key('device-c-20')));
      final actions = find.byKey(const Key('deviceActions-c-20'));
      expectClearOfNavigationBar(tester, actions);
      await tester.tap(actions);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('revoke')), findsOneWidget);
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
      // Revoked, it can only be deleted.
      await openActions(tester, tablet);
      expect(find.byKey(const Key('delete')), findsOneWidget);
      expect(find.byKey(const Key('revoke')), findsNothing);
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

      await choose(tester, tablet, 'revoke');
      await tester.tap(find.byKey(const Key('confirm')));
      await settle(tester);

      expect(backend.otherClients.first['revokedAt'], isNull);
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

    testWidgets('a used code is announced and its device listed on return', (
      tester,
    ) async {
      backend.pairingExpiresAt = DateTime.now().add(
        const Duration(minutes: 10),
      );
      await openDevices(tester);
      await createPairing(tester, 'New tablet');

      backend.usePairing('New tablet');
      await tester.pump(ConnectDeviceScreen.pollInterval);
      await settle(tester);

      expect(
        find.text('"New tablet" connected with the pairing code.'),
        findsOneWidget,
      );
      expect(find.byType(PairingQr), findsNothing);
      expect(find.byKey(const Key('createPairing')), findsOneWidget);
      await goBack(tester);
      expect(inDevice('paired-0', find.text('New tablet')), findsOneWidget);
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
