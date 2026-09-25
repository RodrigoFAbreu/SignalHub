/// A push notification about an event, independent of the push provider.
///
/// The backend's push carries the event's title and message, and data with
/// `eventId`, `category` and `severity` (docs/architecture.md, "Push
/// dispatch"). A push is a signal to look; the event itself is read from the
/// API.
class PushNotice {
  const PushNotice({
    required this.title,
    this.body,
    this.eventId,
    this.opened = false,
  });

  final String title;
  final String? body;

  /// The event the push is about, or `null` for a push that is not about an
  /// event.
  final String? eventId;

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
