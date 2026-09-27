import 'server_credentials.dart';

/// A pairing URI the operator made for this device
/// (`signalhub://pair?server=<address>&code=<code>`, docs/architecture.md,
/// "Pairing"): where the server is and the one-time code to redeem there.
class PairingUri {
  const PairingUri._(this.serverUrl, this.code);

  /// Reads a scanned or pasted pairing URI. Throws [FormatException] with a
  /// message fit for the setup screen.
  factory PairingUri.parse(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null || !uri.isScheme('signalhub') || uri.host != 'pair') {
      throw const FormatException(invalid);
    }
    final serverUrl = ServerCredentials.parseServerUrl(
      uri.queryParameters['server'] ?? '',
    );
    final code = uri.queryParameters['code'] ?? '';
    if (serverUrl == null || !code.startsWith(codePrefix)) {
      throw const FormatException(invalid);
    }
    return PairingUri._(serverUrl, code);
  }

  static const codePrefix = 'shpc1_';

  static const invalid =
      'This is not a SignalHub pairing code. '
      'It is a link that starts with signalhub://pair';

  /// The server address without a trailing slash.
  final String serverUrl;

  /// A one-time bearer credential. Never logged or shown.
  final String code;

  @override
  String toString() => 'PairingUri($serverUrl)';
}
