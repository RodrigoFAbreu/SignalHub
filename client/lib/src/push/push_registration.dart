import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/signalhub_api.dart';
import 'push_service.dart';

/// Whether this installation receives pushes.
enum PushStatus {
  /// The build has no push provider configured, and cannot take one from
  /// the server.
  unavailable('Push is not configured in this build'),

  /// The build has no push options of its own and the server serves none.
  notConfigured('Push is not configured on this server'),

  /// The server's push options are not for this app's provider and platform,
  /// or are malformed.
  unsupported("This server's push configuration does not work with this app"),

  /// Push was set up with other options, served by another server or before
  /// the operator changed them; the provider takes new ones only on a new
  /// start.
  restartRequired('Restart SignalHub to receive pushes from this server'),

  /// Not registered yet, or registration is in progress.
  pending('Registering for push notifications…'),

  /// The owner did not allow notifications.
  permissionDenied('Notifications are not allowed for SignalHub'),

  /// The provider could not issue a token, or the server did not take it.
  failed('Push registration failed; pull down to retry'),

  /// The server has this installation's push target.
  registered('Push notifications are on');

  const PushStatus(this.description);

  final String description;
}

/// Keeps the backend's push target for this installation in step with the
/// push provider's token, through `PUT /api/v1/client/push-target`.
class PushRegistration {
  PushRegistration(this._push, this._api);

  final PushService _push;
  final SignalHubApi _api;
  StreamSubscription<String>? _refreshes;

  /// Registers the current token. Safe to repeat: the backend replaces the
  /// target, and one token belongs to one client.
  Future<PushStatus> register() async {
    if (!await _push.requestPermission()) return PushStatus.permissionDenied;
    final token = await _push.getToken();
    if (token == null) return PushStatus.failed;
    try {
      await _api.setPushTarget(_push.provider, token);
    } on ApiException catch (e) {
      debugPrint('Push target not set: ${e.message}');
      return PushStatus.failed;
    }
    _refreshes ??= _push.tokenRefreshes.listen(_update);
    return PushStatus.registered;
  }

  /// Stops pushes to this installation: removes the target from the server
  /// (best effort, since the key may already be revoked) and the token from
  /// the provider.
  Future<void> unregister() async {
    await dispose();
    try {
      await _api.deletePushTarget();
    } on ApiException catch (e) {
      debugPrint('Push target not removed: ${e.message}');
    }
    await _push.deleteToken();
  }

  Future<void> dispose() async {
    await _refreshes?.cancel();
    _refreshes = null;
  }

  Future<void> _update(String token) async {
    try {
      await _api.setPushTarget(_push.provider, token);
    } on ApiException catch (e) {
      // The next start registers the current token again.
      debugPrint('Refreshed push token not registered: ${e.message}');
    }
  }
}
