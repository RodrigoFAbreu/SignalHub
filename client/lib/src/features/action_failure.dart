import '../api/signalhub_api.dart';

/// Why a change a person asked for did not happen, as the screens say it. The
/// controllers map the server's answers to these, so a screen never shows a
/// server's own title.
enum FailureKind {
  /// The name is taken (an invitation).
  nameTaken,

  /// The person was removed meanwhile.
  removed,

  /// The person is an admin, whom no device changes.
  adminTarget,

  /// The device is an admin's, which no device renames, revokes or deletes.
  adminDevice,

  /// A mod's last active device cannot be revoked.
  lastActiveDevice,

  /// The device is gone from the server.
  gone,

  /// The server is too old for it.
  unsupported,

  /// The server refused what the role allows, and the role did not change.
  notAllowed,

  /// No answer from the server; trying again may work.
  offline,

  /// Anything else the server refused.
  other,

  /// Nothing to say: the key was no longer accepted (setup says why), or the
  /// role changed (the shell says so and the screens follow it).
  quiet,
}

class ActionFailure {
  const ActionFailure(this.kind, this.message);

  /// Nothing to show: see [FailureKind.quiet].
  const ActionFailure.quiet() : kind = FailureKind.quiet, message = '';

  final FailureKind kind;

  /// A sentence for the person: what happened and what to do.
  final String message;

  bool get isQuiet => kind == FailureKind.quiet;

  /// Whether a snackbar offers Retry: only for what trying again may fix.
  bool get canRetry => kind == FailureKind.offline || kind == FailureKind.other;

  /// `Couldn't [what]. Check your connection and try again.`, or without the
  /// connection when the server did answer.
  factory ActionFailure.generic(ApiException e, String what) =>
      e.statusCode == null
      ? ActionFailure(
          FailureKind.offline,
          "Couldn't $what. Check your connection and try again.",
        )
      : ActionFailure(FailureKind.other, "Couldn't $what. Try again.");

  /// For a `403` whose role did not change: the role simply may not.
  static const notAllowedMessage =
      "Your role doesn't allow that. Ask an admin of this server.";
}

/// "Ana's" for a name, in a sentence.
String possessive(String name) => "$name's";
