import 'package:flutter/foundation.dart';

import 'alert_platform.dart';
import 'alert_settings.dart';

/// This installation's alert settings: read from the device at start, saved
/// on the device at every change, and previewed as they are chosen. The
/// server knows nothing of them.
class AlertController extends ChangeNotifier {
  AlertController(this._platform);

  final AlertPlatform _platform;

  /// The settings in use; the defaults until [load] has read the saved ones.
  AlertSettings settings = AlertSettings.defaults;

  /// Reads the saved settings. With none saved yet (a new installation, or
  /// one updated from a version without them), saves the defaults, so the
  /// platform plays them from the first push.
  Future<void> load() async {
    try {
      final stored = AlertSettings.fromStored(await _platform.load());
      if (stored == null) {
        await _platform.save(settings.toPlatform());
      } else {
        settings = stored;
        notifyListeners();
      }
    } on Exception catch (e) {
      debugPrint('Alert settings not read: ${e.runtimeType}');
    }
  }

  /// Saves [next] and previews the part that changed: its sound (at its
  /// volume) or its vibration. Returns a message for the owner when the
  /// setting was not saved or the phone kept the preview quiet, or `null`.
  Future<String?> change(AlertSettings next) async {
    final previous = settings;
    if (next == previous) return null;
    settings = next;
    notifyListeners();
    try {
      await _platform.save(next.toPlatform());
    } on Exception catch (e) {
      debugPrint('Alert settings not saved: ${e.runtimeType}');
      settings = previous;
      notifyListeners();
      return 'The alert setting could not be saved';
    }
    return next.vibration != previous.vibration
        ? preview(next.copyWith(sound: () => null))
        : preview(next.copyWith(vibration: AlertVibration.off));
  }

  /// Plays [alert] once. Returns a message when there is nothing to play or
  /// the phone keeps it quiet, or `null` once played.
  Future<String?> preview(AlertSettings alert) async {
    if (alert.sound == null && alert.vibration == AlertVibration.off) {
      return null;
    }
    try {
      if (await _platform.preview(alert.toPlatform())) return null;
    } on Exception catch (e) {
      debugPrint('Alert not previewed: ${e.runtimeType}');
      return 'The alert could not be played';
    }
    return 'Silent mode or Do Not Disturb is on: the phone keeps the alert '
        'quiet, as it will for pushes';
  }
}
