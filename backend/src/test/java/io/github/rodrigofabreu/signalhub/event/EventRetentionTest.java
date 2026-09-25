package io.github.rodrigofabreu.signalhub.event;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import io.agroal.api.AgroalDataSource;
import io.github.rodrigofabreu.signalhub.TestClients;
import io.github.rodrigofabreu.signalhub.TestProducers;
import io.micrometer.core.instrument.MeterRegistry;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.QuarkusTestProfile;
import io.quarkus.test.junit.TestProfile;
import jakarta.inject.Inject;
import java.sql.SQLException;
import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;

/**
 * Deleting events older than the retention period, on real PostgreSQL. Events are stored in 2000,
 * with the retention job's clock set to then, so events of other tests are never old enough.
 */
@QuarkusTest
@TestProfile(EventRetentionTest.Profile.class)
class EventRetentionTest {

  private static final Instant NOW = Instant.parse("2000-06-01T00:00:00Z");

  @Inject EventRetention retention;
  @Inject AgroalDataSource dataSource;
  @Inject MeterRegistry registry;

  @Test
  void deletesEventsOlderThanTheRetentionPeriodOnly() throws SQLException {
    var producerId = TestProducers.register("retention").id();
    var expired = insertEvent(producerId, NOW.minus(Duration.ofDays(30)).minusMillis(1));
    var kept = insertEvent(producerId, NOW.minus(Duration.ofDays(30)));
    var recent = insertEvent(producerId, NOW.minus(Duration.ofDays(1)));
    var deletedBefore = deleted();

    assertEquals(1, retention.deleteExpired(NOW));

    assertEquals(0, count("events WHERE id = '" + expired + "'"));
    assertEquals(1, count("events WHERE id = '" + kept + "'"));
    assertEquals(1, count("events WHERE id = '" + recent + "'"));
    assertEquals(deletedBefore + 1, deleted());
    // Nothing is left to delete.
    assertEquals(0, retention.deleteExpired(NOW));
  }

  @Test
  void anExpiredEventsPendingPushAndRetriesGoWithIt() throws SQLException {
    var producerId = TestProducers.register("retention-push").id();
    var clientId = TestClients.register("retention-push").id();
    var createdAt = NOW.minus(Duration.ofDays(60));
    var eventId = insertEvent(producerId, createdAt);
    execute(
        "INSERT INTO push_dispatches (event_id, created_at) VALUES ('%s', '%s')"
            .formatted(eventId, createdAt));
    execute(
        ("INSERT INTO push_retries (event_id, client_id, attempts, next_attempt_at)"
                + " VALUES ('%s', '%s', 1, '%s')")
            .formatted(eventId, clientId, createdAt));

    assertEquals(1, retention.deleteExpired(NOW));

    assertEquals(0, count("push_dispatches WHERE event_id = '" + eventId + "'"));
    assertEquals(0, count("push_retries WHERE event_id = '" + eventId + "'"));
    // The client is untouched.
    assertEquals(1, count("clients WHERE id = '" + clientId + "'"));
  }

  @Test
  void deletesMoreEventsThanOneBatchHolds() throws SQLException {
    var producerId = TestProducers.register("retention-batches").id();
    var events = EventRetention.BATCH_SIZE * 2 + 3;
    execute(
        ("INSERT INTO events (id, producer_id, category, severity, title, metadata, created_at)"
                + " SELECT gen_random_uuid(), '%s', 'INFO', 'LOW', 'Old', '{}',"
                + " '%s'::timestamptz - make_interval(days => 31, secs => n)"
                + " FROM generate_series(1, %d) AS n")
            .formatted(producerId, NOW, events));

    assertEquals(events, retention.deleteExpired(NOW));
    assertEquals(0, count("events WHERE producer_id = '" + producerId + "'"));
  }

  @Test
  void retentionShorterThanADayStopsStartup() {
    assertThrows(
        IllegalStateException.class, () -> EventRetention.check(Optional.of(Duration.ofHours(23))));
    assertDoesNotThrow(() -> EventRetention.check(Optional.of(Duration.ofDays(1))));
    assertDoesNotThrow(() -> EventRetention.check(Optional.empty()));
  }

  private UUID insertEvent(UUID producerId, Instant createdAt) throws SQLException {
    var id = UUID.randomUUID();
    execute(
        ("INSERT INTO events (id, producer_id, category, severity, title, metadata, created_at)"
                + " VALUES ('%s', '%s', 'INFO', 'LOW', 'Retention', '{}', '%s')")
            .formatted(id, producerId, createdAt));
    return id;
  }

  private void execute(String sql) throws SQLException {
    try (var connection = dataSource.getConnection();
        var statement = connection.createStatement()) {
      statement.executeUpdate(sql);
    }
  }

  private long count(String fromWhere) throws SQLException {
    try (var connection = dataSource.getConnection();
        var statement = connection.createStatement();
        var rows = statement.executeQuery("SELECT count(*) FROM " + fromWhere)) {
      rows.next();
      return rows.getLong(1);
    }
  }

  private double deleted() {
    return registry.get("signalhub.events.deleted").counter().count();
  }

  public static class Profile implements QuarkusTestProfile {
    @Override
    public Map<String, String> getConfigOverrides() {
      // The documented format, so the test also covers how the setting is parsed.
      return Map.of("signalhub.events.retention", "30d");
    }
  }
}
