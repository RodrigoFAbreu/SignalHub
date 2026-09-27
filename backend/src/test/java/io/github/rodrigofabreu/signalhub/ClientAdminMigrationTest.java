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
 * Upgrading a database that already holds clients and pairings: V13 makes none of them an admin, so
 * the operator has nothing to do. Runs Flyway directly on its own PostgreSQL.
 */
class ClientAdminMigrationTest {

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
  void existingClientsAndPairingsAreNotAdmins() throws SQLException {
    migrate(MigrationVersion.fromVersion("12"));
    try (var connection = connect()) {
      execute(
          connection,
          "INSERT INTO clients (id, name, key_hash, created_at, revoked_at) VALUES"
              + " (gen_random_uuid(), 'active', sha256('a'), now(), NULL),"
              + " (gen_random_uuid(), 'revoked', sha256('r'), now(), now())");
      execute(
          connection,
          "INSERT INTO pairings (id, code_hash, client_name, created_at, expires_at) VALUES"
              + " (gen_random_uuid(), sha256('p'), 'pending', now(), now() + interval '10"
              + " minutes')");
    }

    migrate(MigrationVersion.LATEST);

    try (var connection = connect()) {
      assertEquals(2, count(connection, "SELECT count(*) FROM clients WHERE NOT admin"));
      assertEquals(1, count(connection, "SELECT count(*) FROM pairings WHERE NOT admin"));
      // New rows default to not being admins too, whatever inserts them.
      execute(
          connection,
          "INSERT INTO clients (id, name, key_hash, created_at) VALUES"
              + " (gen_random_uuid(), 'new', sha256('n'), now())");
      assertEquals(0, count(connection, "SELECT count(*) FROM clients WHERE admin"));
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
