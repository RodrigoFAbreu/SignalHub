import 'dart:convert';

import 'package:flutter/services.dart';

/// The app's port to the platform code that plays the alert. Android's
/// (`AlertPlayer.kt`) stores what [save] gives it on the device and plays it
/// itself when a push arrives in the background (client/README.md, "Alert").
abstract interface class AlertPlatform {
  /// What [save] stored last, or `null` if nothing was saved yet.
  Future<String?> load();

  /// Stores [alert] (`AlertSettings.toPlatform`) for the pushes to come.
  Future<void> save(Map<String, Object?> alert);

  /// Plays [alert] once, as a push would. Returns `false` when the phone's
  /// silent mode or do-not-disturb keeps it quiet.
  Future<bool> preview(Map<String, Object?> alert);

  /// Whether the owner gave the app Do Not Disturb access, without which
  /// Android keeps it from sounding during do-not-disturb.
  Future<bool> doNotDisturbAccess();

  /// Opens the system screen where the owner gives that access.
  Future<void> openDoNotDisturbAccess();
}

/// [AlertPlatform] over a method channel to the Android app.
class MethodChannelAlertPlatform implements AlertPlatform {
  static const _channel = MethodChannel(
    'io.github.rodrigofabreu.signalhub/alert',
  );

  @override
  Future<String?> load() => _channel.invokeMethod<String>('load');

  @override
  Future<void> save(Map<String, Object?> alert) =>
      _channel.invokeMethod<void>('save', jsonEncode(alert));

  @override
  Future<bool> preview(Map<String, Object?> alert) async =>
      await _channel.invokeMethod<bool>('preview', jsonEncode(alert)) ?? false;

  @override
  Future<bool> doNotDisturbAccess() async =>
      await _channel.invokeMethod<bool>('doNotDisturbAccess') ?? false;

  @override
  Future<void> openDoNotDisturbAccess() =>
      _channel.invokeMethod<void>('openDoNotDisturbAccess');
}
