package io.github.rodrigofabreu.signalhub;

import static org.junit.jupiter.api.Assertions.assertEquals;

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
 * Upgrading a database that already holds clients: V20 makes every one a device that never expires,
 * so no device is signed out by the upgrade and the operator has nothing to do. Runs Flyway
 * directly on its own PostgreSQL.
 */
class BrowserSignInMigrationTest {

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
  void existingClientsStayDevicesThatNeverExpire() throws SQLException {
    migrate(MigrationVersion.fromVersion("19"));
    try (var connection = connect()) {
      execute(
          connection,
          "INSERT INTO clients (id, name, key_hash, created_at, revoked_at, user_id) VALUES"
              + " (gen_random_uuid(), 'active', sha256('a'), now(), NULL, (SELECT id FROM users)),"
              + " (gen_random_uuid(), 'revoked', sha256('r'), now(), now(),"
              + " (SELECT id FROM users))");
    }

    migrate(MigrationVersion.LATEST);

    try (var connection = connect()) {
      assertEquals(
          2,
          count(
              connection,
              "SELECT count(*) FROM clients WHERE kind = 'DEVICE' AND expires_at IS NULL"));
      // A client written without saying what it is stays a device, whatever inserts it.
      execute(
          connection,
          "INSERT INTO clients (id, name, key_hash, created_at, user_id) VALUES"
              + " (gen_random_uuid(), 'new', sha256('n'), now(), (SELECT id FROM users))");
      assertEquals(3, count(connection, "SELECT count(*) FROM clients WHERE kind = 'DEVICE'"));
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

  private static long count(Connection connection, String query) throws SQLException {
    try (var rows = connection.createStatement().executeQuery(query)) {
      rows.next();
      return rows.getLong(1);
    }
  }
}
