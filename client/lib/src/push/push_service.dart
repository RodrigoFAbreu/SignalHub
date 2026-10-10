/// A push notification, independent of the push provider: about an event, or
/// a notice about a device.
///
/// The backend's push about an event carries its title and message, and data
/// with `eventId`, `category` and `severity` (docs/architecture.md, "Push
/// dispatch"). A device notice (a device paired or was revoked) has the data
/// `notice` instead, and no event. A push is a signal to look; the event
/// itself is read from the API.
class PushNotice {
  const PushNotice({
    required this.title,
    this.body,
    this.eventId,
    this.opened = false,
    this.data = const {},
  });

  final String title;
  final String? body;

  /// The event the push is about, or `null` for a push that is not about an
  /// event.
  final String? eventId;

  /// The push's data as the provider delivered it.
  final Map<String, String> data;

  /// What kind of device notice this is (`client-paired`, `client-revoked`,
  /// …), or `null` for a push about an event. A notice is not an event: it
  /// has no row in the inbox, and opening it shows the devices.
  String? get notice => data['notice'];

  /// Whether the owner opened the app by tapping the notification, rather
  /// than receiving it while the app was in the foreground.
  final bool opened;
}

/// The app's port to a push provider. Everything provider-specific stays
/// behind it, the way `PushProvider` does in the backend: the rest of the app
/// sees only a provider name, an opaque token and [PushNotice]s.
abstract interface class PushService {
  /// The `provider` of this installation's push target, as the backend knows
  /// the provider.
  String get provider;

  /// Asks the platform for permission to show notifications. Returns whether
  /// notifications may be shown.
  Future<bool> requestPermission();

  /// The provider's token for this installation, or `null` if the provider
  /// cannot issue one right now.
  Future<String?> getToken();

  /// New tokens the provider issued after [getToken].
  Stream<String> get tokenRefreshes;

  /// Pushes received while the app runs, and the one that opened it. It may
  /// be listened to once.
  Stream<PushNotice> get notices;

  /// Invalidates this installation's token, so it no longer receives pushes.
  Future<void> deleteToken();
}
