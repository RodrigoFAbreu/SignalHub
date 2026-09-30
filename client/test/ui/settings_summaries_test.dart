import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/alert/alert_settings.dart';
import 'package:signalhub_client/src/models/client_registration.dart';
import 'package:signalhub_client/src/models/event.dart';
import 'package:signalhub_client/src/ui/alert_section.dart';
import 'package:signalhub_client/src/ui/push_filters.dart';

void main() {
  group('the push filters summary', () {
    const producers = [
      EventProducer(id: 'p-1', name: 'ci'),
      EventProducer(id: 'p-2', name: 'nas'),
      EventProducer(id: 'p-3', name: 'backup'),
    ];

    String summary(PushPreferences preferences) =>
        PushFilters.summary(preferences, producers);

    test('names the minimum severity', () {
      for (final (severity, text) in [
        ('LOW', 'All severities'),
        ('NORMAL', 'Normal and up'),
        ('HIGH', 'High and up'),
        ('CRITICAL', 'Critical only'),
        ('SOMETHING_NEW', 'All severities'),
      ]) {
        expect(
          summary(PushPreferences(minimumSeverity: severity)),
          startsWith('$text · '),
        );
      }
    });

    test('names the muted categories in the order they are listed', () {
      expect(
        summary(
          const PushPreferences(
            mutedCategories: ['INFO', 'ACTION_REQUIRED', 'UNKNOWN_ONE'],
          ),
        ),
        'All severities · Action required, Info muted · all producers',
      );
    });

    test('names up to two muted producers, by name or else by ID', () {
      expect(
        summary(const PushPreferences(mutedProducerIds: ['p-2', 'p-gone'])),
        endsWith(' · nas, p-gone muted'),
      );
      expect(
        summary(const PushPreferences(mutedProducerIds: ['p-1', 'p-2', 'p-3'])),
        endsWith(' · 3 producers muted'),
      );
    });
  });

  test('the alert summary leaves out what does not play', () {
    expect(
      GeneralAlertSection.alertSummary(
        const AlertSettings(
          sound: null,
          volume: 60,
          vibration: AlertVibration.light,
          pattern: AlertPattern.heartbeat,
          length: AlertLength.medium,
        ),
      ),
      'No sound · Light · Heartbeat · Medium',
    );
  });
}
