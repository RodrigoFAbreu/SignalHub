/// Which SignalHub build this app is: the release version names an official
/// artifact, the commit names the exact source.
///
/// Both come in at build time as `--dart-define`s, never from the placeholder
/// `version:` of `pubspec.yaml`. Only the release's own app build sets
/// `SIGNALHUB_VERSION`, so a local build from a release's tag never claims to
/// be that release; the documented build commands set `SIGNALHUB_REVISION`.
class BuildIdentity {
  const BuildIdentity({this.version = '', this.revision = ''});

  /// The identity compiled into this build.
  static const compiled = BuildIdentity(
    version: String.fromEnvironment('SIGNALHUB_VERSION'),
    revision: String.fromEnvironment('SIGNALHUB_REVISION'),
  );

  /// The release version, `X.Y.Z`; empty for a development build.
  final String version;

  /// The full commit the app was built from; empty if the build was not
  /// given it.
  final String revision;

  String get versionLine =>
      version.isEmpty ? 'SignalHub development build' : 'SignalHub $version';

  String get commitLine => revision.isEmpty
      ? 'Commit unknown'
      : 'Commit ${revision.length > 7 ? revision.substring(0, 7) : revision}';
}
