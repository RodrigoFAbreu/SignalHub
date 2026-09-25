package io.github.rodrigofabreu.signalhub;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.agroal.api.AgroalDataSource;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.QuarkusTestProfile;
import io.quarkus.test.junit.TestProfile;
import jakarta.inject.Inject;
import java.sql.SQLException;
import java.util.List;
import java.util.Map;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.MigrationState;
import org.junit.jupiter.api.Test;

/**
 * Proves the production Flyway setup applies migrations at startup against real PostgreSQL. A
 * test-only migration is added next to the real ones, on a dedicated database so it cannot leak
 * into other tests.
 */
@QuarkusTest
@TestProfile(FlywayStartupMigrationTest.Profile.class)
class FlywayStartupMigrationTest {

  @Inject Flyway flyway;
  @Inject AgroalDataSource dataSource;

  @Test
  void migrationsAreAppliedAtStartup() throws SQLException {
    var probe = flyway.info().current();
    assertEquals("9999", probe.getVersion().getVersion());
    assertEquals(MigrationState.SUCCESS, probe.getState());
    assertEquals(0, flyway.info().pending().length);

    try (var connection = dataSource.getConnection();
        var rows =
            connection.createStatement().executeQuery("SELECT note FROM flyway_startup_probe")) {
      assertTrue(rows.next());
      assertEquals("applied by Flyway", rows.getString(1));
    }
  }

  public static class Profile implements QuarkusTestProfile {
    @Override
    public Map<String, String> getConfigOverrides() {
      return Map.of("quarkus.flyway.locations", "db/migration,db/test-migration");
    }

    @Override
    public List<TestResourceEntry> testResources() {
      return List.of(new TestResourceEntry(DedicatedPostgres.class));
    }
  }
}
