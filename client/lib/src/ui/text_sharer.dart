import 'package:flutter/services.dart';

/// Hands [text] to the platform's share sheet; returns whether it opened.
/// Tests replace the platform.
typedef TextSharer = Future<bool> Function(String text);

const _channel = MethodChannel('io.github.rodrigofabreu.signalhub/share');

/// Shares [text] through the platform's own share sheet (Android's chooser,
/// iOS's activity sheet), over a method channel to the app's platform code, so
/// the app needs no sharing package. A platform without it shares nothing.
Future<bool> shareText(String text) async {
  try {
    return await _channel.invokeMethod<bool>('text', text) ?? false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}
