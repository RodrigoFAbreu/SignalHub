import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../models/push_config.dart';
import 'push_service.dart';

/// [PushService] over Firebase Cloud Messaging, the backend's `fcm` provider.
///
/// This file is the only code that knows about Firebase. On iOS, FCM relays through APNs; the Firebase SDK handles that.
class FirebasePushService implements PushService {
  FirebasePushService._(this._messaging);

  /// Starts Firebase when the build carries Firebase options, and returns
  /// `null` otherwise, so a build without them runs without push.
  static Future<PushService?> start() async {
    final options = firebaseOptionsFrom(
      _buildEnvironment,
      defaultTargetPlatform,
    );
    if (options == null) return null;
    return _startWith(options);
  }

  /// Starts Firebase with the options the server serves, for a build without
  /// its own. Returns `null`, leaving push off, when they are not complete
  /// and well-formed FCM options for this platform, or Firebase refuses them.
  /// Firebase starts once per process, so this is called at most once with
  /// options that work.
  static Future<PushService?> startServed(PushConfig served) async {
    if (served.provider != fcmProvider) return null;
    final options = servedFirebaseOptionsFrom(
      served.options,
      defaultTargetPlatform,
    );
    if (options == null) return null;
    try {
      return await _startWith(options);
    } on Exception catch (e) {
      // Firebase or the platform refused them; never log the options.
      debugPrint('Served Firebase options refused: ${e.runtimeType}');
      return null;
    }
  }

  static Future<PushService> _startWith(FirebaseOptions options) async {
    await Firebase.initializeApp(options: options);
    final service = FirebasePushService._(FirebaseMessaging.instance);
    await service._listen();
    return service;
  }

  final FirebaseMessaging _messaging;
  // Single-subscription, so it buffers the push that opened the app until the
  // app listens.
  final _notices = StreamController<PushNotice>();

  @override
  String get provider => fcmProvider;

  @override
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission();
    return switch (settings.authorizationStatus) {
      AuthorizationStatus.authorized || AuthorizationStatus.provisional => true,
      _ => false,
    };
  }

  @override
  Future<String?> getToken() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS &&
          !await _apnsTokenArrived()) {
        return null;
      }
      return await _messaging.getToken();
    } on FirebaseException catch (e) {
      debugPrint('No FCM token: ${e.code}');
      return null;
    }
  }

  @override
  Stream<String> get tokenRefreshes => _messaging.onTokenRefresh;

  @override
  Stream<PushNotice> get notices => _notices.stream;

  @override
  Future<void> deleteToken() => _messaging.deleteToken();

  Future<void> _listen() async {
    FirebaseMessaging.onMessage.listen((m) => _notices.add(_notice(m, false)));
    FirebaseMessaging.onMessageOpenedApp.listen(
      (m) => _notices.add(_notice(m, true)),
    );
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _notices.add(_notice(initial, true));
  }

  /// FCM issues no token on iOS until APNs has given the app its device
  /// token, which can take a moment after permission is granted.
  Future<bool> _apnsTokenArrived() async {
    for (var attempt = 0; attempt < 10; attempt++) {
      if (await _messaging.getAPNSToken() != null) return true;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  static PushNotice _notice(RemoteMessage message, bool opened) => PushNotice(
    title: message.notification?.title ?? 'SignalHub',
    body: message.notification?.body,
    eventId: message.data['eventId'] as String?,
    opened: opened,
  );
}

/// The Firebase project's app options, passed at build time with
/// `--dart-define-from-file=firebase-options.json` (see the client README).
/// They identify the owner's own Firebase project, so they are not committed.
const _buildEnvironment = {
  'FIREBASE_PROJECT_ID': String.fromEnvironment('FIREBASE_PROJECT_ID'),
  'FIREBASE_MESSAGING_SENDER_ID': String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  ),
  'FIREBASE_ANDROID_API_KEY': String.fromEnvironment(
    'FIREBASE_ANDROID_API_KEY',
  ),
  'FIREBASE_ANDROID_APP_ID': String.fromEnvironment('FIREBASE_ANDROID_APP_ID'),
  'FIREBASE_IOS_API_KEY': String.fromEnvironment('FIREBASE_IOS_API_KEY'),
  'FIREBASE_IOS_APP_ID': String.fromEnvironment('FIREBASE_IOS_APP_ID'),
};

/// The backend's name for Firebase Cloud Messaging.
const fcmProvider = 'fcm';

/// The bundle ID the iOS app is registered with in Firebase.
const iosBundleId = 'io.github.rodrigofabreu.signalhub';

/// Firebase options for [platform] from [environment], or `null` when any of
/// them is missing or the platform is not supported.
@visibleForTesting
FirebaseOptions? firebaseOptionsFrom(
  Map<String, String> environment,
  TargetPlatform platform,
) {
  final prefix = switch (platform) {
    TargetPlatform.android => 'FIREBASE_ANDROID',
    TargetPlatform.iOS => 'FIREBASE_IOS',
    _ => null,
  };
  if (prefix == null) return null;
  String? value(String name) {
    final v = environment[name]?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  final projectId = value('FIREBASE_PROJECT_ID');
  final senderId = value('FIREBASE_MESSAGING_SENDER_ID');
  final apiKey = value('${prefix}_API_KEY');
  final appId = value('${prefix}_APP_ID');
  if (projectId == null ||
      senderId == null ||
      apiKey == null ||
      appId == null) {
    return null;
  }
  return FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: senderId,
    projectId: projectId,
    iosBundleId: platform == TargetPlatform.iOS ? iosBundleId : null,
  );
}

/// Firebase options for [platform] from options a server served, or `null`
/// when they are incomplete or malformed. They are checked more strictly than
/// the build's own, since the app did not choose them: the sender ID is a
/// number and the app ID is Firebase's `1:<sender ID>:<platform>:<hex>` for
/// this platform, so options of another project's app or platform are
/// refused before Firebase starts.
@visibleForTesting
FirebaseOptions? servedFirebaseOptionsFrom(
  Map<String, String> served,
  TargetPlatform platform,
) {
  final options = firebaseOptionsFrom(served, platform);
  if (options == null) return null;
  final sender = options.messagingSenderId;
  final platformName = platform == TargetPlatform.iOS ? 'ios' : 'android';
  final appId = RegExp('^1:${RegExp.escape(sender)}:$platformName:[0-9a-f]+\$');
  if (!RegExp(r'^[0-9]+$').hasMatch(sender) || !appId.hasMatch(options.appId)) {
    return null;
  }
  return options;
}
