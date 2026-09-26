import 'json.dart';

/// The options an app needs to set up push with the server's provider
/// (`GET /api/v1/client/push-config`). The options are opaque to SignalHub:
/// only the push service for [provider] reads them.
class PushConfig {
  const PushConfig({required this.provider, required this.options});

  factory PushConfig.fromJson(Map<String, Object?> json) {
    final options = json.object('options');
    return PushConfig(
      provider: json.string('provider'),
      options: {for (final name in options.keys) name: options.string(name)},
    );
  }

  final String provider;
  final Map<String, String> options;

  /// Whether [other] names the same provider and options.
  bool sameAs(PushConfig other) =>
      provider == other.provider &&
      options.length == other.options.length &&
      options.entries.every((e) => other.options[e.key] == e.value);
}
