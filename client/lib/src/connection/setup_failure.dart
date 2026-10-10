/// Why connecting this installation to a server failed, in the words the
/// setup screen says it in: one plain sentence on what happened and what to
/// do, never blaming the person.
enum SetupFailureKind {
  /// What was scanned or pasted is not a pairing code.
  notInvitation,

  /// It is the code a web page shows to sign a browser in.
  webSignIn,

  /// The server did not accept the code. It answers the same for an expired,
  /// a used and an unknown one, so the app cannot say which.
  codeRejected,

  /// The server could not be reached. A network failure does not use up a
  /// code, so trying again may use it.
  unreachable,

  /// The server answered with an error.
  serverProblem,

  /// The server answered with something the app does not understand.
  unexpectedAnswer,

  /// The server address typed is not one.
  badAddress,

  /// The client key typed is not one.
  badKey,

  /// The server did not accept the client key.
  keyRejected,
}

class SetupFailure {
  const SetupFailure(this.kind, this.message);

  /// "Can't reach HOST. …", naming the address the code or the owner gave, so
  /// a wrong one is easy to spot.
  factory SetupFailure.unreachable(String host) => SetupFailure(
    SetupFailureKind.unreachable,
    "Can't reach $host. Check your connection and that the address is "
    'right, then try again.',
  );

  static const notInvitation = SetupFailure(
    SetupFailureKind.notInvitation,
    "That isn't a SignalHub invitation. Scan the code the person who invited "
    'you shared.',
  );

  static const webSignIn = SetupFailure(
    SetupFailureKind.webSignIn,
    "That's a sign-in code for a web page. Use Settings › Sign in a browser.",
  );

  static const serverProblem = SetupFailure(
    SetupFailureKind.serverProblem,
    'SignalHub had a problem. Try again in a moment.',
  );

  static const unexpectedAnswer = SetupFailure(
    SetupFailureKind.unexpectedAnswer,
    'The server sent an unexpected answer. Try again in a moment.',
  );

  static const keyRejected = SetupFailure(
    SetupFailureKind.keyRejected,
    "That key isn't valid, or its device was disconnected.",
  );

  final SetupFailureKind kind;

  /// The sentence for the owner.
  final String message;

  /// Whether the same code or key may work if tried again: nothing was
  /// refused, the server was only out of reach or in trouble.
  bool get canRetry =>
      kind == SetupFailureKind.unreachable ||
      kind == SetupFailureKind.serverProblem ||
      kind == SetupFailureKind.unexpectedAnswer;
}

/// The neutral sentence for a device the server no longer accepts: a revoked
/// device and a removed person are the same `401` to it, so one sentence
/// covers both, and says nothing the person did wrong.
const noLongerConnectedMessage =
    'This device is no longer connected to SignalHub. To use it again, ask '
    'for a new code, or ask the host.';
