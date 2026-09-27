import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens an event's link outside the app; returns whether it opened. Tests
/// replace the platform.
typedef LinkOpener = Future<bool> Function(Uri link);

/// Hands [link] to the system browser, or to the app the platform assigns to
/// it, never to a browser inside SignalHub.
Future<bool> openLink(Uri link) async {
  try {
    return await launchUrl(link, mode: LaunchMode.externalApplication);
  } on PlatformException {
    return false;
  }
}
