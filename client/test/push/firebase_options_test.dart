import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/push/firebase_push_service.dart';

void main() {
  const environment = {
    'FIREBASE_PROJECT_ID': 'my-project',
    'FIREBASE_MESSAGING_SENDER_ID': '1234',
    'FIREBASE_ANDROID_API_KEY': 'android-key',
    'FIREBASE_ANDROID_APP_ID': '1:1234:android:ab',
    'FIREBASE_IOS_API_KEY': 'ios-key',
    'FIREBASE_IOS_APP_ID': '1:1234:ios:cd',
  };

  test('builds Android options from the Android values', () {
    final options = firebaseOptionsFrom(environment, TargetPlatform.android)!;

    expect(options.projectId, 'my-project');
    expect(options.messagingSenderId, '1234');
    expect(options.apiKey, 'android-key');
    expect(options.appId, '1:1234:android:ab');
    expect(options.iosBundleId, isNull);
  });

  test('builds iOS options with the app bundle ID', () {
    final options = firebaseOptionsFrom(environment, TargetPlatform.iOS)!;

    expect(options.apiKey, 'ios-key');
    expect(options.appId, '1:1234:ios:cd');
    expect(options.iosBundleId, iosBundleId);
  });

  test('without the values, push is off', () {
    expect(firebaseOptionsFrom(const {}, TargetPlatform.android), isNull);
    expect(
      firebaseOptionsFrom({
        ...environment,
        'FIREBASE_IOS_APP_ID': ' ',
      }, TargetPlatform.iOS),
      isNull,
    );
    // Android values alone do not configure iOS.
    expect(
      firebaseOptionsFrom({
        ...environment,
        'FIREBASE_IOS_API_KEY': '',
      }, TargetPlatform.iOS),
      isNull,
    );
  });

  test('platforms other than Android and iOS have no push', () {
    expect(firebaseOptionsFrom(environment, TargetPlatform.linux), isNull);
  });

  group('served options', () {
    test('complete options for this platform are accepted', () {
      final android = servedFirebaseOptionsFrom(
        environment,
        TargetPlatform.android,
      )!;
      final ios = servedFirebaseOptionsFrom(environment, TargetPlatform.iOS)!;

      expect(android.appId, '1:1234:android:ab');
      expect(ios.appId, '1:1234:ios:cd');
      expect(ios.iosBundleId, iosBundleId);
    });

    test('incomplete options are refused', () {
      expect(
        servedFirebaseOptionsFrom({
          ...environment,
          'FIREBASE_ANDROID_API_KEY': '',
        }, TargetPlatform.android),
        isNull,
      );
    });

    test('a sender ID that is not a number is refused', () {
      expect(
        servedFirebaseOptionsFrom({
          ...environment,
          'FIREBASE_MESSAGING_SENDER_ID': 'abc',
          'FIREBASE_ANDROID_APP_ID': '1:abc:android:ab',
        }, TargetPlatform.android),
        isNull,
      );
    });

    test('an app ID of another platform or sender is refused', () {
      for (final appId in [
        '1:1234:ios:ab',
        '1:9999:android:ab',
        '1:1234:android:',
        '1:1234:android:ab:extra',
        'android-app',
      ]) {
        expect(
          servedFirebaseOptionsFrom({
            ...environment,
            'FIREBASE_ANDROID_APP_ID': appId,
          }, TargetPlatform.android),
          isNull,
          reason: appId,
        );
      }
    });

    test('platforms other than Android and iOS have no push', () {
      expect(
        servedFirebaseOptionsFrom(environment, TargetPlatform.linux),
        isNull,
      );
    });
  });
}
