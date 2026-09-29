import 'package:flutter/foundation.dart';

import 'alert_platform.dart';
import 'alert_settings.dart';

/// This installation's alert settings, the general alert and critical
/// pushes': read from the device at start, saved on the device at every
/// change, and previewed as they are chosen. The server knows nothing of
/// them.
class AlertController extends ChangeNotifier {
  AlertController(this._platform);

  final AlertPlatform _platform;

  /// The general alert in use; the defaults until [load] has read the saved
  /// one.
  AlertSettings settings = AlertSettings.defaults;

  /// How critical pushes alert; the defaults until [load] has read the
  /// saved settings.
  CriticalAlertSettings critical = CriticalAlertSettings.defaults;

  /// Whether the app has Do Not Disturb access, as last read; `false` until
  /// [load] or [refreshDoNotDisturbAccess] has read it.
  bool doNotDisturbAccess = false;

  /// Whether critical pushes sound during Do Not Disturb: chosen, and
  /// allowed by the phone.
  bool get criticalDuringDoNotDisturb =>
      critical.duringDoNotDisturb && doNotDisturbAccess;

  /// Reads the saved settings. With none saved yet (a new installation, or
  /// one updated from a version without them), saves the defaults, so the
  /// platform plays them from the first push; likewise the critical
  /// settings next to a general alert saved by a version without them.
  Future<void> load() async {
    try {
      final stored = await _platform.load();
      final general = AlertSettings.fromStored(stored);
      final critical = CriticalAlertSettings.fromStored(stored);
      if (general != null) settings = general;
      if (critical != null) this.critical = critical;
      if (general != null || critical != null) notifyListeners();
      if (general == null || critical == null) {
        await _platform.save(platformAlerts(settings, this.critical));
      }
    } on Exception catch (e) {
      debugPrint('Alert settings not read: ${e.runtimeType}');
    }
    await refreshDoNotDisturbAccess();
  }

  /// Reads again whether the app has Do Not Disturb access, which the owner
  /// gives or takes away in the phone's settings.
  Future<void> refreshDoNotDisturbAccess() async {
    bool access;
    try {
      access = await _platform.doNotDisturbAccess();
    } on Exception catch (e) {
      debugPrint('Do Not Disturb access not read: ${e.runtimeType}');
      access = false;
    }
    if (access != doNotDisturbAccess) {
      doNotDisturbAccess = access;
      notifyListeners();
    }
  }

  /// Saves [next] as the general alert and previews the part that changed:
  /// its sound (at its volume) or its vibration. Returns a message for the
  /// owner when the setting was not saved or the phone kept the preview
  /// quiet, or `null`.
  Future<String?> change(AlertSettings next) async {
    final previous = settings;
    if (next == previous) return null;
    if (!await _save(next, critical)) {
      return 'The alert setting could not be saved';
    }
    return preview(_changedPart(previous, next));
  }

  /// Saves [next] as the critical pushes' settings, and previews the part of
  /// their own alert that changed. Turning on [CriticalAlertSettings
  /// .duringDoNotDisturb] without Do Not Disturb access opens the system
  /// screen to give it instead, and saves nothing. Returns a message for the
  /// owner, or `null`.
  Future<String?> changeCritical(CriticalAlertSettings next) async {
    final previous = critical;
    if (next == previous) return null;
    if (next.duringDoNotDisturb && !criticalDuringDoNotDisturb) {
      await refreshDoNotDisturbAccess();
      if (!doNotDisturbAccess) return _askForDoNotDisturbAccess();
    }
    if (!await _save(settings, next)) {
      return 'The alert setting could not be saved';
    }
    if (!next.different || next.alert == previous.alert) return null;
    return previewCritical(_changedPart(previous.alert, next.alert));
  }

  /// Plays [alert] once as the general alert. Returns a message when there
  /// is nothing to play or the phone keeps it quiet, or `null` once played.
  Future<String?> preview(AlertSettings alert) => _play(alert.toPlatform());

  /// Plays [alert] once as a critical push's own, sounding on silent or
  /// during Do Not Disturb as the critical settings say.
  Future<String?> previewCritical(AlertSettings alert) => _play(
    critical.copyWith(different: true, alert: alert).toPlatform(settings),
  );

  Future<bool> _save(
    AlertSettings general,
    CriticalAlertSettings critical,
  ) async {
    final (previousGeneral, previousCritical) = (settings, this.critical);
    settings = general;
    this.critical = critical;
    notifyListeners();
    try {
      await _platform.save(platformAlerts(general, critical));
      return true;
    } on Exception catch (e) {
      debugPrint('Alert settings not saved: ${e.runtimeType}');
      settings = previousGeneral;
      this.critical = previousCritical;
      notifyListeners();
      return false;
    }
  }

  Future<String> _askForDoNotDisturbAccess() async {
    try {
      await _platform.openDoNotDisturbAccess();
    } on Exception catch (e) {
      debugPrint('Do Not Disturb access not opened: ${e.runtimeType}');
      return 'Give SignalHub Do Not Disturb access in the phone\'s settings '
          'first';
    }
    return 'Allow SignalHub in Do Not Disturb access, then turn this on '
        'again';
  }

  /// The alert to preview for a change: the new vibration alone, or the
  /// sound at its volume alone.
  static AlertSettings _changedPart(
    AlertSettings previous,
    AlertSettings next,
  ) => next.vibration != previous.vibration
      ? next.copyWith(sound: () => null)
      : next.copyWith(vibration: AlertVibration.off);

  Future<String?> _play(Map<String, Object?> alert) async {
    if (alert['resource'] == null && (alert['timings'] as List).isEmpty) {
      return null;
    }
    try {
      if (await _platform.preview(alert)) return null;
    } on Exception catch (e) {
      debugPrint('Alert not previewed: ${e.runtimeType}');
      return 'The alert could not be played';
    }
    return 'Silent mode or Do Not Disturb is on: the phone keeps the alert '
        'quiet, as it will for pushes';
  }
}
