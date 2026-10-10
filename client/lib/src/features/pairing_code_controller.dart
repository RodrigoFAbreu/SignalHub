import 'package:flutter/foundation.dart';

import '../api/signalhub_api.dart';
import '../api_gateway.dart';
import '../connection/pairing_uri.dart';
import '../models/client_registration.dart';
import 'action_failure.dart';

/// One pairing code on its way to a new device: made for an invitation or by
/// _Connect a device_, shown as a QR code with a countdown, and asked about
/// until a device uses it or it runs out (`/api/v1/client/pairings`). Lives
/// as long as the screen that shows it, so the code is not kept in memory
/// longer than it is on screen.
class PairingCodeController extends ChangeNotifier {
  /// [serverUrl] is the address this device reaches the server at, for the
  /// link of a server that has no public address configured.
  PairingCodeController(
    this.gateway, {
    required this.serverUrl,
    this.now = DateTime.now,
  });

  final ApiGateway gateway;
  final String serverUrl;
  final DateTime Function() now;

  /// The code being shown; `null` before one is made.
  DevicePairing? pairing;

  /// The name of the device that used the code, once one has.
  String? usedBy;

  /// Whether a code is being made.
  bool creating = false;

  /// Why the last code could not be made; `null` if it was.
  ActionFailure? failure;

  bool _statusUnknown = false;
  bool _asking = false;
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// The link a new device opens or scans to pair: the server's own pairing
  /// URI or, when it has no public address, one for the address this device
  /// reaches it at.
  String? get link {
    final pairing = this.pairing;
    if (pairing == null) return null;
    return pairing.uri ?? PairingUri.format(serverUrl, pairing.code);
  }

  bool get isUsed => usedBy != null;

  /// Whether the code stopped working without being used.
  bool get isExpired {
    final pairing = this.pairing;
    return pairing != null && !isUsed && !pairing.expiresAt.isAfter(now());
  }

  /// How long the code still works.
  Duration get left => pairing?.expiresAt.difference(now()) ?? Duration.zero;

  /// Shows a code something else made, such as an invitation's.
  void show(DevicePairing made) {
    pairing = made;
    usedBy = null;
    failure = null;
    _statusUnknown = false;
    notifyListeners();
  }

  /// Forgets the code, so the screen is back to asking for a name.
  void forget() {
    pairing = null;
    usedBy = null;
    _statusUnknown = false;
    notifyListeners();
  }

  /// Makes a code for a new device named [deviceName], for [userId] or, when
  /// that is `null`, for this device's own user. [personName] is who the
  /// code is for, for the message when they were removed meanwhile.
  Future<void> create(
    String deviceName, {
    String? userId,
    String? personName,
  }) async {
    creating = true;
    failure = null;
    notifyListeners();
    try {
      show(
        await gateway.call(
          (api) => api.createPairing(deviceName.trim(), userId: userId),
        ),
      );
    } on SignedOutException {
      failure = const ActionFailure.quiet();
    } on ApiException catch (e) {
      failure = _failure(e, userId: userId, personName: personName);
    } finally {
      creating = false;
      notifyListeners();
    }
  }

  ActionFailure _failure(ApiException e, {String? userId, String? personName}) {
    final status = e.statusCode;
    if (status == 403) {
      // The role was read again: if it no longer pairs, the screen follows.
      return gateway.role.managesDevices
          ? const ActionFailure(
              FailureKind.notAllowed,
              ActionFailure.notAllowedMessage,
            )
          : const ActionFailure.quiet();
    }
    // Naming a user is only for an admin: a server that knows users answers
    // `404` (unknown) or `409` (removed) for who is gone.
    if (userId != null && (status == 404 || status == 409)) {
      return ActionFailure(
        FailureKind.removed,
        "${possessive(personName ?? 'That person')} access was removed. "
        'Choose someone else.',
      );
    }
    if (status == 404) {
      return const ActionFailure(
        FailureKind.unsupported,
        'This server cannot create pairing codes from a device. Update '
        'SignalHub, or create the code on the admin page.',
      );
    }
    return ActionFailure.generic(e, 'make the code');
  }

  /// Asks the server whether the code shown was used and by which device;
  /// nothing is asked when the server cannot say or the answer is known.
  /// Failures are left to the next time it asks.
  Future<void> check() async {
    final asked = pairing;
    final id = asked?.id;
    if (id == null || _statusUnknown || _asking || isUsed) return;
    _asking = true;
    try {
      final status = await gateway.call((api) => api.getPairingStatus(id));
      // A code made or forgotten meanwhile is not the one asked about.
      if (!identical(pairing, asked) || !status.isRedeemed) return;
      usedBy = status.clientName;
      notifyListeners();
    } on SignedOutException {
      return;
    } on ApiException catch (e) {
      switch (e.statusCode) {
        // A server released before the status, or a role that no longer
        // may ask: nothing to ask any more.
        case 403 || 404 || 405 when identical(pairing, asked):
          _statusUnknown = true;
        default:
          debugPrint('Pairing status not read: ${e.message}');
      }
    } finally {
      _asking = false;
    }
  }
}
