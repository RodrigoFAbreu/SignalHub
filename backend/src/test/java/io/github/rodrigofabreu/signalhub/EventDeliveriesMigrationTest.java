package io.github.rodrigofabreu.signalhub;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.MigrationVersion;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.testcontainers.postgresql.PostgreSQLContainer;

/**
 * Upgrading a database that already holds events and clients: V16 adds an empty table of delivery
 * records, so the operator has nothing to do, and the records go with their event or client. Runs
 * Flyway directly on its own PostgreSQL.
 */
class EventDeliveriesMigrationTest {

  private static final String EVENT = "01997d5e-8a3c-7b1e-9f2a-4c6d8e0f1a2b";
  private static final String CLIENT = "01997d5e-8a3c-7b1e-9f2a-4c6d8e0f1a2c";

  private static PostgreSQLContainer postgres;

  @BeforeAll
  static void startPostgres() {
    postgres = new PostgreSQLContainer("postgres:18-alpine");
    postgres.start();
  }

  @AfterAll
  static void stopPostgres() {
    postgres.stop();
  }

  @Test
  void existingEventsHaveNoRecordsAndRecordsGoWithTheirEventOrClient() throws SQLException {
    // Up to V16 only: V17 gives every client a user, which these inserts do not know about.
    migrate(MigrationVersion.fromVersion("15"));
    try (var connection = connect()) {
      execute(
          connection,
          "INSERT INTO producers (id, name, created_at) VALUES"
              + " (gen_random_uuid(), 'migration', now())");
      execute(
          connection,
          "INSERT INTO events (id, producer_id, category, severity, title, metadata, created_at)"
              + " SELECT '"
              + EVENT
              + "', id, 'INFO', 'LOW', 'Before', '{}', now() FROM producers");
      execute(
          connection,
          "INSERT INTO clients (id, name, key_hash, created_at) VALUES ('"
              + CLIENT
              + "', 'phone', sha256('c'), now())");
    }

    migrate(MigrationVersion.fromVersion("16"));

    try (var connection = connect()) {
      assertEquals(0, count(connection, "SELECT count(*) FROM event_deliveries"));
      execute(connection, record("DELIVERED", 1));
      execute(connection, record("TRANSIENT_FAILURE", 2));
      // Only the known outcomes, and attempts from 1.
      assertThrows(SQLException.class, () -> execute(connection, record("SHOWN", 1)));
      assertThrows(SQLException.class, () -> execute(connection, record("DELIVERED", 0)));

      execute(connection, "DELETE FROM clients WHERE id = '" + CLIENT + "'");
      assertEquals(0, count(connection, "SELECT count(*) FROM event_deliveries"));
      execute(
          connection,
          "INSERT INTO clients (id, name, key_hash, created_at) VALUES ('"
              + CLIENT
              + "', 'phone', sha256('c'), now())");
      execute(connection, record("DELIVERED", 1));
      execute(connection, "DELETE FROM events WHERE id = '" + EVENT + "'");
      assertEquals(0, count(connection, "SELECT count(*) FROM event_deliveries"));
    }
  }

  private static String record(String outcome, int attempt) {
    return "INSERT INTO event_deliveries (event_id, client_id, attempt, outcome, at) VALUES ('"
        + EVENT
        + "', '"
        + CLIENT
        + "', "
        + attempt
        + ", '"
        + outcome
        + "', now())";
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

  private static long count(Connection connection, String query) throws SQLException {
    try (var rows = connection.createStatement().executeQuery(query)) {
      rows.next();
      return rows.getLong(1);
    }
  }
}
