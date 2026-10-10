import 'server_credentials.dart';

/// What a web page shows to sign a browser in with this app: a link
/// (`signalhub://signin?server=<address>&code=shsc1_...`, the QR code and the
/// page's _Open the app_ button) or a short code to type (`K7Q-4MX`).
class WebSignInLink {
  const WebSignInLink._(this.serverUrl, this.code);

  /// Reads a scanned or opened link. Returns `null` for anything that is not
  /// a sign-in link.
  static WebSignInLink? tryParse(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null || !uri.isScheme('signalhub') || uri.host != 'signin') {
      return null;
    }
    final serverUrl = ServerCredentials.parseServerUrl(
      uri.queryParameters['server'] ?? '',
    );
    final code = uri.queryParameters['code'] ?? '';
    if (serverUrl == null || !code.startsWith(codePrefix)) return null;
    return WebSignInLink._(serverUrl, code);
  }

  static const codePrefix = 'shsc1_';

  /// The address of the server whose page showed the link.
  final String serverUrl;

  /// A short-lived credential for one sign-in. Never logged or shown.
  final String code;

  /// Whether the link names the server at [address], however each spells it:
  /// the scheme and host in any case, a default port left out, a trailing
  /// slash or not.
  bool isFor(String address) => _sameServer(serverUrl, address);

  @override
  String toString() => 'WebSignInLink($serverUrl)';
}

bool _sameServer(String a, String b) {
  final first = Uri.tryParse(a);
  final second = Uri.tryParse(b);
  if (first == null || second == null) return false;
  String path(Uri uri) => uri.path.replaceAll(RegExp(r'/+$'), '');
  return first.scheme.toLowerCase() == second.scheme.toLowerCase() &&
      first.host.toLowerCase() == second.host.toLowerCase() &&
      first.port == second.port &&
      path(first) == path(second);
}

/// The short code a page shows to sign a browser in without a camera, six
/// characters shown as `K7Q-4MX`.
///
/// The server settles what a code is; the app only keeps a code that cannot
/// be one from using up one of the few wrong tries a device has: the wrong
/// length, or a character the codes never use (no `I`, `L`, `O`, `0` or `1`).
/// Case, a dash and spaces do not matter.
class WebSignInCode {
  const WebSignInCode._();

  static const length = 6;
  static final _alphabet = RegExp(r'^[A-HJKMNP-Z2-9]+$');

  /// Whether [typed] is the length of a code and made of letters and digits:
  /// enough to ask, since a wrong character is said as a wrong code.
  static bool isComplete(String typed) {
    final letters = normalize(typed);
    return letters.length == length && RegExp(r'^[A-Z0-9]+$').hasMatch(letters);
  }

  /// Whether [typed] can be a code the server made.
  static bool isPlausible(String typed) {
    final letters = normalize(typed);
    return letters.length == length && _alphabet.hasMatch(letters);
  }

  /// [typed] without its dash and spaces, in capitals.
  static String normalize(String typed) =>
      typed.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
}
