import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// What a connected device still has to tell its owner, once.
enum OnboardingStep {
  /// The device connected in this version of the app: the welcome comes
  /// before the inbox.
  welcome,

  /// The device was already connected when the app updated: a card at the top
  /// of the inbox lists what changed.
  whatsNew,

  /// Nothing more to say.
  done,
}

/// Keeps which [OnboardingStep] the device is at, on the device, across
/// restarts. A device that has no record was connected before this was kept:
/// it is one that was already connected when the app updated.
abstract interface class OnboardingStore {
  /// The step saved last, or `null` if none was.
  Future<OnboardingStep?> load();

  Future<void> save(OnboardingStep step);
}

/// Stores the step in the platform's secure storage, the one store the app
/// already keeps on the device; nothing in it is secret.
class SecureOnboardingStore implements OnboardingStore {
  SecureOnboardingStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'signalhub.onboarding.step';

  final FlutterSecureStorage _storage;

  @override
  Future<OnboardingStep?> load() async {
    final name = await _storage.read(key: _key);
    // A name a later version stored and this one lacks counts as no record.
    return OnboardingStep.values.where((s) => s.name == name).firstOrNull;
  }

  @override
  Future<void> save(OnboardingStep step) =>
      _storage.write(key: _key, value: step.name);
}
