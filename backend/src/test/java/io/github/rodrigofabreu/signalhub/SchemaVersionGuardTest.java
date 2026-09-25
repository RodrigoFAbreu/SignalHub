package io.github.rodrigofabreu.signalhub;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.agroal.api.AgroalDataSource;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.TestProfile;
import jakarta.inject.Inject;
import java.sql.SQLException;
import java.util.Arrays;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.configuration.FluentConfiguration;
import org.junit.jupiter.api.Test;

/**
 * The database of {@link FlywayStartupMigrationTest} carries test migration V9999, so a Flyway that
 * sees only the real migrations stands in for an older release starting on a newer schema.
 */
@QuarkusTest
@TestProfile(FlywayStartupMigrationTest.Profile.class)
class SchemaVersionGuardTest {

  @Inject Flyway flyway;
  @Inject AgroalDataSource dataSource;

  @Test
  void startupMigrationIsGuarded() {
    assertTrue(
        Arrays.stream(flyway.getConfiguration().getCallbacks())
            .anyMatch(SchemaVersionGuard.class::isInstance));
  }

  @Test
  void olderReleaseRefusesNewerSchema() throws SQLException {
    assertRefused(release("db/migration"));
  }

  @Test
  void olderReleaseRefusesNewerSchemaWithoutValidation() throws SQLException {
    var configuration = Flyway.configure().validateOnMigrate(false);
    assertRefused(release(configuration, "db/migration"));
  }

  @Test
  void sameReleaseStarts() throws SQLException {
    var applied = appliedMigrations();

    var result = release("db/migration", "db/test-migration").migrate();

    assertEquals(0, result.migrationsExecuted);
    assertEquals(applied, appliedMigrations());
  }

  private void assertRefused(Flyway olderRelease) throws SQLException {
    var applied = appliedMigrations();

    var error = assertThrows(RuntimeException.class, olderRelease::migrate);

    var messages = messages(error);
    assertTrue(messages.contains("migrations 9999 are unknown to this release"), messages);
    assertFalse(messages.contains("repair"), messages);
    assertEquals(applied, appliedMigrations());
  }

  private Flyway release(String... locations) {
    return release(Flyway.configure(), locations);
  }

  private Flyway release(FluentConfiguration configuration, String... locations) {
    configuration.dataSource(dataSource).locations(locations);
    new SchemaVersionGuard().customize(configuration);
    return configuration.load();
  }

  private int appliedMigrations() throws SQLException {
    try (var connection = dataSource.getConnection();
        var rows =
            connection
                .createStatement()
                .executeQuery("SELECT count(*) FROM flyway_schema_history")) {
      rows.next();
      return rows.getInt(1);
    }
  }

  private static String messages(Throwable error) {
    var text = new StringBuilder();
    for (var cause = error; cause != null; cause = cause.getCause()) {
      text.append(cause.getMessage()).append('\n');
    }
    return text.toString();
  }
}
