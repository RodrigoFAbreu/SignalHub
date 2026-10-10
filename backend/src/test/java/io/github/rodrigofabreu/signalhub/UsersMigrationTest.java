package io.github.rodrigofabreu.signalhub;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.MigrationVersion;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.testcontainers.postgresql.PostgreSQLContainer;

/**
 * Upgrading a database from before users (V16) that holds a single owner's data: the owner becomes
 * the first user, an admin, and keeps every client, pairing, producer, subscription and read mark,
 * so they see, receive and can do what they did before. Runs Flyway directly on its own PostgreSQL.
 */
class UsersMigrationTest {

  private PostgreSQLContainer postgres;

  // A database per test: each starts from its own version.
  @BeforeEach
  void startPostgres() {
    postgres = new PostgreSQLContainer("postgres:18-alpine");
    postgres.start();
  }

  @AfterEach
  void stopPostgres() {
    postgres.stop();
  }

  @Test
  void theExistingDataBecomesTheFirstUsersAnAdmin() throws SQLException {
    migrate(MigrationVersion.fromVersion("16"));
    try (var connection = connect()) {
      execute(
          connection,
          "INSERT INTO producers (id, name, created_at) VALUES"
              + " (gen_random_uuid(), 'ci', now()), (gen_random_uuid(), 'backups', now())");
      execute(
          connection,
          "INSERT INTO producer_api_keys (id, producer_id, key_hash, created_at)"
              + " SELECT gen_random_uuid(), id, sha256('k'), now() FROM producers");
      execute(
          connection,
          "INSERT INTO events (id, producer_id, category, severity, title, metadata, created_at,"
              + " read_at) SELECT gen_random_uuid(), id, 'INFO', 'LOW', 'Read before', '{}',"
              + " now(), now() FROM producers WHERE name = 'ci'");
      execute(
          connection,
          "INSERT INTO events (id, producer_id, category, severity, title, metadata, created_at)"
              + " SELECT gen_random_uuid(), id, 'INFO', 'LOW', 'Unread before', '{}', now()"
              + " FROM producers WHERE name = 'ci'");
      execute(
          connection,
          "INSERT INTO clients (id, name, key_hash, created_at, revoked_at, admin) VALUES"
              + " (gen_random_uuid(), 'phone', sha256('a'), now(), NULL, true),"
              + " (gen_random_uuid(), 'tablet', sha256('b'), now(), NULL, false),"
              + " (gen_random_uuid(), 'old', sha256('c'), now(), now(), false)");
      execute(
          connection,
          "INSERT INTO pairings (id, code_hash, client_name, created_at, expires_at, admin) VALUES"
              + " (gen_random_uuid(), sha256('p'), 'pending', now(), now() + interval '10 minutes',"
              + " false)");
    }

    migrate(MigrationVersion.LATEST);

    try (var connection = connect()) {
      // One user, an admin: the owner, named so that the operator can rename them.
      assertEquals(1, count(connection, "SELECT count(*) FROM users"));
      assertEquals(
          1,
          count(
              connection,
              "SELECT count(*) FROM users WHERE role = 'ADMIN' AND revoked_at IS NULL"
                  + " AND name = 'Owner'"));
      // Every client and pairing is theirs, whatever their admin flag was, and the flag is gone.
      assertEquals(
          3,
          count(connection, "SELECT count(*) FROM clients WHERE user_id = (SELECT id FROM users)"));
      assertEquals(
          1,
          count(
              connection, "SELECT count(*) FROM pairings WHERE user_id = (SELECT id FROM users)"));
      assertEquals(
          0,
          count(
              connection,
              "SELECT count(*) FROM pg_attribute WHERE attrelid"
                  + " IN ('clients'::regclass, 'pairings'::regclass) AND attname = 'admin'"
                  + " AND NOT attisdropped"));
      // Every producer is theirs, private, and they are subscribed to each.
      assertEquals(
          2,
          count(
              connection,
              "SELECT count(*) FROM producers WHERE owner_id = (SELECT id FROM users)"
                  + " AND visibility = 'PRIVATE'"));
      assertEquals(
          2,
          count(
              connection,
              "SELECT count(*) FROM subscriptions WHERE user_id = (SELECT id FROM users)"));
      // What they had read is read, what they had not is not, and the operator's marks stay.
      assertEquals(1, count(connection, "SELECT count(*) FROM event_reads"));
      assertEquals(
          1,
          count(
              connection,
              "SELECT count(*) FROM event_reads r JOIN events e ON e.id = r.event_id"
                  + " WHERE e.title = 'Read before' AND r.read_at = e.read_at"));
      assertEquals(1, count(connection, "SELECT count(*) FROM events WHERE read_at IS NOT NULL"));
      // Nothing is lost: the keys, the events and the revoked client are as they were.
      assertEquals(2, count(connection, "SELECT count(*) FROM producer_api_keys"));
      assertEquals(2, count(connection, "SELECT count(*) FROM events"));
      assertEquals(
          1, count(connection, "SELECT count(*) FROM clients WHERE revoked_at IS NOT NULL"));
    }
  }

  @Test
  void theSchemaKeepsTheRulesOfRolesAndNames() throws SQLException {
    migrate(MigrationVersion.LATEST);
    try (var connection = connect()) {
      // Only the three roles.
      assertThrows(
          SQLException.class,
          () ->
              execute(
                  connection,
                  "INSERT INTO users (id, name, role, created_at)"
                      + " VALUES (gen_random_uuid(), 'x', 'OWNER', now())"));
      // A revoked user is never an admin.
      assertThrows(
          SQLException.class,
          () ->
              execute(
                  connection,
                  "INSERT INTO users (id, name, role, created_at, revoked_at)"
                      + " VALUES (gen_random_uuid(), 'y', 'ADMIN', now(), now())"));
      // Names are unique ignoring case.
      execute(
          connection,
          "INSERT INTO users (id, name, role, created_at)"
              + " VALUES (gen_random_uuid(), 'Anna', 'BASIC', now())");
      assertThrows(
          SQLException.class,
          () ->
              execute(
                  connection,
                  "INSERT INTO users (id, name, role, created_at)"
                      + " VALUES (gen_random_uuid(), 'ANNA', 'BASIC', now())"));
      // A client and a producer always have a user, and a producer is public or private.
      assertThrows(
          SQLException.class,
          () ->
              execute(
                  connection,
                  "INSERT INTO clients (id, name, key_hash, created_at)"
                      + " VALUES (gen_random_uuid(), 'x', sha256('z'), now())"));
      assertThrows(
          SQLException.class,
          () ->
              execute(
                  connection,
                  "INSERT INTO producers (id, name, created_at, owner_id, visibility)"
                      + " SELECT gen_random_uuid(), 'p', now(), id, 'SECRET' FROM users LIMIT 1"));
    }
  }

  private void migrate(MigrationVersion target) {
    Flyway.configure()
        .dataSource(postgres.getJdbcUrl(), postgres.getUsername(), postgres.getPassword())
        .locations("classpath:db/migration")
        .target(target)
        .load()
        .migrate();
  }

  private Connection connect() throws SQLException {
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
