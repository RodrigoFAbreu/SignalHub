import 'api/signalhub_api.dart';
import 'models/users.dart';

/// What the feature controllers (producers, people, devices) need of the app:
/// the API with its failures handled the one way every screen agrees on.
abstract interface class ApiGateway {
  /// What the signed-in user may do, as the server last said.
  UserRole get role;

  /// The signed-in user's ID and name; `null` before the registration is read.
  String? get userId;
  String? get userName;

  /// Runs [call] against the server. Failures are the call's own
  /// [ApiException]s, except two the app handles for everyone:
  ///
  /// - the server no longer accepts this key (`401`): the app forgets the
  ///   connection and returns to setup, and this throws [SignedOutException],
  ///   which a caller ends quietly, since setup says why;
  /// - the server refuses what the role allows (`403`): the app reads the
  ///   registration again, so a changed role rebuilds the screens, and the
  ///   [ApiException] is rethrown for the caller to show.
  Future<T> call<T>(Future<T> Function(SignalHubApi api) call);
}

/// The key was no longer accepted and the app is back at setup: nothing more
/// to show for the call that failed.
class SignedOutException extends ApiException {
  const SignedOutException()
    : super('This device is no longer connected', statusCode: 401);
}

/// A list a screen reads from the server, with what it needs to show it:
/// skeleton rows while the first read runs, the older list under a banner
/// when a refresh fails, a plain error with Try again when there is no older
/// list.
class Resource<T> {
  Resource();

  /// The last list read; `null` until one has been.
  T? value;

  /// Whether a read is running.
  bool loading = false;

  /// Why the last read failed; `null` if it worked.
  ApiException? error;

  /// When [value] was read.
  DateTime? loadedAt;

  bool get hasValue => value != null;

  /// Nothing to show yet and a read is running: skeleton rows.
  bool get showSkeleton => value == null && error == null;

  /// The first read failed: an empty state with Try again.
  bool get failedWithoutList => value == null && error != null;

  /// A refresh failed and the older list stays under a banner.
  bool get stale => value != null && error != null;

  /// The last read got no answer at all: the connection is down.
  bool get offline => error != null && error!.statusCode == null;

  /// Runs [read] and keeps its answer. Returns whether it worked; a
  /// [SignedOutException] leaves everything as it was and returns `false`.
  Future<bool> load(Future<T> Function() read) async {
    loading = true;
    try {
      value = await read();
      loadedAt = DateTime.now();
      error = null;
      return true;
    } on SignedOutException {
      return false;
    } on ApiException catch (e) {
      error = e;
      return false;
    } finally {
      loading = false;
    }
  }

  void clear() {
    value = null;
    loading = false;
    error = null;
    loadedAt = null;
  }
}
