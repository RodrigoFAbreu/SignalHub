import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the phone's settings page of this app, where the camera is allowed.
/// Tests replace the platform.
typedef AppSettingsOpener = Future<void> Function();

const _channel = MethodChannel('io.github.rodrigofabreu.signalhub/app');

/// Opens the system's settings page of this app: on iOS through the
/// `app-settings:` link, on Android through the activity's own channel
/// (`MainActivity.kt`). Not being able to open it changes nothing else.
Future<void> openAppSettings() async {
  try {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await launchUrl(Uri.parse('app-settings:'));
    } else {
      await _channel.invokeMethod<void>('openAppSettings');
    }
  } on PlatformException catch (e) {
    debugPrint('App settings not opened: ${e.code}');
  } on MissingPluginException {
    debugPrint('App settings not opened: no platform');
  }
}
