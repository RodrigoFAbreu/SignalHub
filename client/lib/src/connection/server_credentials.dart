import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The SignalHub server this installation talks to and its client key.
class ServerCredentials {
  const ServerCredentials._(this.baseUrl, this.clientKey);

  /// Validates what the owner typed. Throws [FormatException] with a message
  /// fit for the setup screen.
  factory ServerCredentials.parse(String serverUrl, String clientKey) {
    final url = serverUrl.trim();
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !(uri.isScheme('https') || uri.isScheme('http')) ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException(
        'Enter the server address, for example https://signalhub.example.org',
      );
    }
    final key = clientKey.trim();
    // Keys carry a public format prefix (docs/architecture.md, "Client keys"),
    // which catches the most likely mix-up: pasting a producer key.
    if (!key.startsWith(clientKeyPrefix)) {
      throw const FormatException(
        'Enter a client key (it starts with $clientKeyPrefix)',
      );
    }
    return ServerCredentials._(_withoutTrailingSlash(url), key);
  }

  static const clientKeyPrefix = 'shck1_';

  /// The server address without a trailing slash, so API paths can be
  /// appended. It may include a path when a reverse proxy serves SignalHub
  /// below one.
  final String baseUrl;

  /// A bearer credential. Never logged or shown after setup.
  final String clientKey;

  Uri endpoint(String path) => Uri.parse('$baseUrl/$path');

  @override
  String toString() => 'ServerCredentials($baseUrl)';

  static String _withoutTrailingSlash(String url) => url.endsWith('/')
      ? _withoutTrailingSlash(url.substring(0, url.length - 1))
      : url;
}

/// Keeps the credentials across app restarts.
abstract interface class CredentialsStore {
  Future<ServerCredentials?> load();

  Future<void> save(ServerCredentials credentials);

  Future<void> clear();
}

/// Stores the credentials in the platform's secure storage: the Keychain on
/// iOS, and Keystore-backed encryption on Android.
class SecureCredentialsStore implements CredentialsStore {
  SecureCredentialsStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _urlKey = 'signalhub.serverUrl';
  static const _clientKeyKey = 'signalhub.clientKey';

  final FlutterSecureStorage _storage;

  @override
  Future<ServerCredentials?> load() async {
    final url = await _storage.read(key: _urlKey);
    final key = await _storage.read(key: _clientKeyKey);
    if (url == null || key == null) return null;
    try {
      return ServerCredentials.parse(url, key);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> save(ServerCredentials credentials) async {
    await _storage.write(key: _urlKey, value: credentials.baseUrl);
    await _storage.write(key: _clientKeyKey, value: credentials.clientKey);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _clientKeyKey);
    await _storage.delete(key: _urlKey);
  }
}
