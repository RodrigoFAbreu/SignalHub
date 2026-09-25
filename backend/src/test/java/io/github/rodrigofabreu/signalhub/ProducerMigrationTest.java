package io.github.rodrigofabreu.signalhub;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.util.HashMap;
import java.util.Map;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.MigrationVersion;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.testcontainers.postgresql.PostgreSQLContainer;

/**
 * Upgrading a database that already holds unauthenticated events: V2 turns each distinct {@code
 * source} into a producer and binds the events to it. Runs Flyway directly on its own PostgreSQL.
 */
class ProducerMigrationTest {

  private static PostgreSQLContainer postgres;

  @BeforeAll
  static void startPostgres() {
    postgres = new PostgreSQLContainer("postgres:17-alpine");
    postgres.start();
  }

  @AfterAll
  static void stopPostgres() {
    postgres.stop();
  }

  @Test
  void existingEventsAreBoundToProducersNamedAfterTheirSource() throws SQLException {
    migrate(MigrationVersion.fromVersion("1"));
    try (var connection = connect()) {
      execute(
          connection,
          "INSERT INTO events (id, source, category, severity, title, metadata, created_at) VALUES"
              + " (gen_random_uuid(), 'ci/runner', 'INFO', 'LOW', 'a', '{}', '2026-01-02Z'),"
              + " (gen_random_uuid(), 'ci/runner', 'INFO', 'LOW', 'b', '{}', '2026-01-01Z'),"
              + " (gen_random_uuid(), 'backup', 'COMPLETED', 'LOW', 'c', '{}', '2026-01-03Z')");
    }

    migrate(MigrationVersion.LATEST);

    try (var connection = connect()) {
      var producers = new HashMap<String, String>();
      try (var rows =
          connection
              .createStatement()
              .executeQuery("SELECT name, created_at::date, disabled_at IS NULL FROM producers")) {
        while (rows.next()) {
          assertTrue(rows.getBoolean(3), "migrated producers are enabled");
          producers.put(rows.getString(1), rows.getString(2));
        }
      }
      // Each producer dates from its oldest event.
      assertEquals(Map.of("ci/runner", "2026-01-01", "backup", "2026-01-03"), producers);

      var owners = new HashMap<String, String>();
      try (var rows =
          connection
              .createStatement()
              .executeQuery(
                  "SELECT e.title, p.name FROM events e JOIN producers p ON p.id = e.producer_id")) {
        while (rows.next()) {
          owners.put(rows.getString(1), rows.getString(2));
        }
      }
      assertEquals(Map.of("a", "ci/runner", "b", "ci/runner", "c", "backup"), owners);

      assertFalse(hasColumn(connection, "events", "source"), "source is replaced by producer_id");
      try (var rows =
          connection.createStatement().executeQuery("SELECT count(*) FROM producer_api_keys")) {
        rows.next();
        assertEquals(0, rows.getInt(1), "migrated producers get keys only from the operator");
      }
    }
  }

  private static void migrate(MigrationVersion target) {
    Flyway.configure()
        .dataSource(postgres.getJdbcUrl(), postgres.getUsername(), postgres.getPassword())
        .locations("classpath:db/migration")
        .target(target)
        .load()
        .migrate();
  }

  private static Connection connect() throws SQLException {
    return DriverManager.getConnection(
        postgres.getJdbcUrl(), postgres.getUsername(), postgres.getPassword());
  }

  private static void execute(Connection connection, String sql) throws SQLException {
    try (var statement = connection.createStatement()) {
      statement.executeUpdate(sql);
    }
  }

  private static boolean hasColumn(Connection connection, String table, String column)
      throws SQLException {
    try (var rows = connection.getMetaData().getColumns(null, "public", table, column)) {
      return rows.next();
    }
  }
}
