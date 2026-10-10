/// What is wrong with a producer name, by the rule the server holds it to.
enum NameProblem { empty, notAllowed, tooLong }

/// The server's rule for a producer name: letters, digits and `. _ : / -`,
/// starting with a letter or a digit, up to 100 characters. The app checks it
/// while the name is typed, so the person is told before asking.
abstract final class ProducerName {
  static const maxLength = 100;

  static final _allowed = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:/-]*$');

  /// What is wrong with [name], or `null` if the server accepts it. A name
  /// that is too long and also has characters it refuses is told as refused:
  /// shortening it would not help.
  static NameProblem? check(String name) {
    if (name.isEmpty) return NameProblem.empty;
    if (!_allowed.hasMatch(name)) return NameProblem.notAllowed;
    if (name.length > maxLength) return NameProblem.tooLong;
    return null;
  }
}
