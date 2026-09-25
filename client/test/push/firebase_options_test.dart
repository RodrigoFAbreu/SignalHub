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
}
