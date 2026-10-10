import 'package:flutter/foundation.dart';

import '../api/signalhub_api.dart';
import '../api_gateway.dart';
import '../connection/web_sign_in_link.dart';
import '../models/client_registration.dart';

/// Where signing a browser in is: waiting for a code, reading one, asking the
/// person, or finished.
enum SignInStep { scanning, checking, confirming, approving, done }

/// Why a sign-in did not go on, in the words the screen says it in: what
/// happened and what to do, never blaming the person.
enum SignInFailureKind {
  /// What was scanned is not a sign-in code of a web page.
  notSignInCode,

  /// The code is of a page of another server than this app is connected to.
  otherServer,

  /// No live sign-in has the code. The server answers the same for a wrong,
  /// a run-out and a used one.
  wrongCode,

  /// This device typed too many wrong codes lately.
  tooManyTries,

  /// The sign-in ended before it was approved.
  gone,

  /// No answer from the server; trying again may work.
  offline,

  /// Anything else the server answered.
  other,
}

class SignInFailure {
  const SignInFailure(this.kind, this.message);

  final SignInFailureKind kind;

  /// A sentence for the person: what happened and what to do.
  final String message;

  /// Whether trying again as it was may work.
  bool get canRetry =>
      kind == SignInFailureKind.offline || kind == SignInFailureKind.other;

  static const notSignInCode = SignInFailure(
    SignInFailureKind.notSignInCode,
    "That isn't a sign-in code from a SignalHub page. Scan the code a web "
    'page shows.',
  );

  /// The server answers every failed code the same, and so does the app.
  static const wrongCode = SignInFailure(
    SignInFailureKind.wrongCode,
    "That code isn't right or has run out. Check the page and try again.",
  );

  static const tooManyTries = SignInFailure(
    SignInFailureKind.tooManyTries,
    'Too many tries. Wait a few minutes, then try again.',
  );

  static const gone = SignInFailure(
    SignInFailureKind.gone,
    'That sign-in has ended. Show a new code on the page and scan it.',
  );

  static const offline = SignInFailure(
    SignInFailureKind.offline,
    "Can't reach SignalHub. Check your connection and try again.",
  );

  static const other = SignInFailure(
    SignInFailureKind.other,
    'SignalHub had a problem. Try again in a moment.',
  );

  factory SignInFailure.otherServer(String address) => SignInFailure(
    SignInFailureKind.otherServer,
    'That code is for another server. This app is connected to $address.',
  );
}

/// Signing a browser in from this device (`/api/v1/client/web-sign-ins`): a
/// web page shows a code, the person scans it or types it here, the app says
/// which browser asked, and the person signs it in or cancels. Lives as long
/// as the screen that does it.
///
/// A code is never signed in on its own: [approve] is the person's answer to
/// the question the confirmation asks, and cancelling tells the page.
class WebSignInController extends ChangeNotifier {
  /// [serverUrl] is the server this device is connected to, the only one it
  /// signs a browser in to.
  WebSignInController(this.gateway, {required this.serverUrl});

  final ApiGateway gateway;
  final String serverUrl;

  SignInStep step = SignInStep.scanning;

  /// The browser that asked, from the lookup until the person answers.
  WebSignIn? request;

  /// Why the last step did not work; `null` if it did.
  SignInFailure? failure;

  /// The name of the browser that was signed in, once it was.
  String? signedIn;

  /// What was last read, so the camera, which sees the same code many times a
  /// second, does not read it again and again, and so it can be tried again.
  String? _lastCode;
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

  /// Reads what the camera saw, or a link the phone opened: a sign-in link of
  /// the page of this app's server. Does nothing while a code is being read or
  /// answered, or for the code that was just read and not signed in.
  Future<void> readScanned(String text) async {
    if (step != SignInStep.scanning || text == _lastCode) return;
    _lastCode = text;
    final link = WebSignInLink.tryParse(text);
    if (link == null) return _fail(SignInFailure.notSignInCode);
    if (!link.isFor(serverUrl)) {
      return _fail(SignInFailure.otherServer(_host(serverUrl)));
    }
    await _lookup(link.code);
  }

  /// Reads the code the person typed on the page's behalf.
  Future<void> readTyped(String typed) async {
    if (step != SignInStep.scanning) return;
    _lastCode = typed;
    // A code that cannot be one is not sent: the server allows only a few
    // wrong tries.
    if (!WebSignInCode.isPlausible(typed)) {
      return _fail(SignInFailure.wrongCode);
    }
    await _lookup(typed.trim());
  }

  /// Tries the last code again, after the server could not be reached.
  Future<void> retry() async {
    final code = _lastCode;
    if (code == null || step != SignInStep.scanning) return;
    _lastCode = null;
    if (WebSignInLink.tryParse(code) != null) {
      await readScanned(code);
    } else {
      await readTyped(code);
    }
  }

  /// Forgets the last failure, as the person changes what they typed.
  void clearFailure() {
    if (failure == null) return;
    failure = null;
    notifyListeners();
  }

  void _fail(SignInFailure failed) {
    failure = failed;
    step = SignInStep.scanning;
    notifyListeners();
  }

  Future<void> _lookup(String code) async {
    step = SignInStep.checking;
    failure = null;
    notifyListeners();
    try {
      request = await gateway.call((api) => api.lookupWebSignIn(code));
      step = SignInStep.confirming;
      notifyListeners();
    } on SignedOutException {
      _quiet();
    } on ApiException catch (e) {
      _fail(switch (e.statusCode) {
        null => SignInFailure.offline,
        404 => SignInFailure.wrongCode,
        429 => SignInFailure.tooManyTries,
        _ => SignInFailure.other,
      });
    }
  }

  /// Signs the browser in: the person said yes. A browser that is no longer
  /// waiting ends the sign-in; a failure that trying again may fix keeps the
  /// question open.
  Future<void> approve() async {
    final asked = request;
    if (asked == null || step != SignInStep.confirming) return;
    step = SignInStep.approving;
    failure = null;
    notifyListeners();
    try {
      await gateway.call((api) => api.approveWebSignIn(asked.id));
      signedIn = asked.browserName;
      request = null;
      step = SignInStep.done;
      notifyListeners();
    } on SignedOutException {
      _quiet();
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        request = null;
        _fail(SignInFailure.gone);
        return;
      }
      failure = e.statusCode == null
          ? SignInFailure.offline
          : SignInFailure.other;
      step = SignInStep.confirming;
      notifyListeners();
    }
  }

  /// The person said no: the page is told, and the code that was read is not
  /// read again while the camera still sees it.
  Future<void> cancel() async {
    final asked = request;
    if (asked == null) return;
    request = null;
    failure = null;
    step = SignInStep.scanning;
    notifyListeners();
    try {
      await gateway.call((api) => api.cancelWebSignIn(asked.id));
    } on ApiException catch (e) {
      // The page stops waiting by itself when the code runs out.
      debugPrint('Sign-in not cancelled: ${e.message}');
    }
  }

  /// The key was no longer accepted and setup says why: nothing to show.
  void _quiet() {
    request = null;
    step = SignInStep.scanning;
    notifyListeners();
  }

  static String _host(String address) =>
      Uri.tryParse(address)?.authority ?? address;
}
