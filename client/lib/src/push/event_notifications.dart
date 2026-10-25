import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Takes the notification of an event off the phone's shade; tests replace
/// it.
typedef NotificationRemover = Future<void> Function(String eventId);

const _channel = MethodChannel(
  'io.github.rodrigofabreu.signalhub/notifications',
);

/// Removes the notification of the event [eventId] through the activity's
/// channel (`MainActivity.kt`), by its tag, the event's ID, as
/// `PushAlertReceiver` does on a notice. A notification already gone, or a
/// platform without the channel, changes nothing else.
Future<void> removeEventNotification(String eventId) async {
  try {
    await _channel.invokeMethod<void>('remove', eventId);
  } on PlatformException catch (e) {
    debugPrint('Notification not removed: ${e.code}');
  } on MissingPluginException {
    debugPrint('Notification not removed: no platform');
  }
}
