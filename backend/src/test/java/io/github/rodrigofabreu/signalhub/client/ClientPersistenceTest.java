package io.github.rodrigofabreu.signalhub.client;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.agroal.api.AgroalDataSource;
import io.github.rodrigofabreu.signalhub.TestClients;
import io.github.rodrigofabreu.signalhub.producer.ApiKeys;
import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;
import java.sql.SQLException;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;

/** What client registration writes to PostgreSQL, and the invariants the schema enforces. */
@QuarkusTest
class ClientPersistenceTest {

  @Inject AgroalDataSource dataSource;

  @Test
  void migrationCreatesTheClientsTable() throws SQLException {
    var columns = new LinkedHashMap<String, String>();
    columns.put("id", "uuid NO");
    columns.put("name", "text NO");
    columns.put("key_hash", "bytea NO");
    columns.put("created_at", "timestamp with time zone NO");
    columns.put("revoked_at", "timestamp with time zone YES");
    columns.put("push_provider", "text YES");
    columns.put("push_token", "text YES");
    columns.put("push_updated_at", "timestamp with time zone YES");
    columns.put("push_enabled", "boolean NO");
    columns.put("push_minimum_severity", "text NO");
    columns.put("push_muted_categories", "ARRAY NO");
    columns.put("push_muted_producers", "ARRAY NO");
    // Added by V12: empty until the client's first push.
    columns.put("last_push_succeeded_at", "timestamp with time zone YES");
    columns.put("last_push_succeeded_event_id", "uuid YES");
    columns.put("last_push_failed_at", "timestamp with time zone YES");
    columns.put("last_push_failed_event_id", "uuid YES");
    columns.put("last_push_failed_result", "text YES");
    // Added by V13: false for every client that existed before.
    columns.put("admin", "boolean NO");
    assertEquals(columns, columnsOf("clients"));
  }

  @Test
  void migrationCreatesThePairingsTable() throws SQLException {
    var columns = new LinkedHashMap<String, String>();
    columns.put("id", "uuid NO");
    columns.put("code_hash", "bytea NO");
    columns.put("client_name", "text NO");
    columns.put("created_at", "timestamp with time zone NO");
    columns.put("expires_at", "timestamp with time zone NO");
    // Added by V13.
    columns.put("admin", "boolean NO");
    // Added by V14: empty for pairings created with the admin token.
    columns.put("created_by", "uuid YES");
    assertEquals(columns, columnsOf("pairings"));
  }

  @Test
  void aPairingIsCreatedOnlyByAKnownClient() {
    var e =
        assertThrows(
            SQLException.class,
            () -> {
              try (var connection = dataSource.getConnection();
                  var statement =
                      connection.prepareStatement(
                          "INSERT INTO pairings (id, code_hash, client_name, created_at,"
                              + " expires_at, created_by) VALUES (gen_random_uuid(),"
                              + " sha256('by'::bytea), 'x', now(), now() + interval '1 minute',"
                              + " gen_random_uuid())")) {
                statement.executeUpdate();
              }
            });
    // foreign_key_violation
    assertEquals("23503", e.getSQLState(), e.getMessage());
  }

  @Test
  void aPairingExpiresAfterItIsCreated() {
    assertRejected("INSERT INTO pairings VALUES (?, sha256('code'::bytea), 'x', now(), now())");
    assertRejected(
        "INSERT INTO pairings VALUES (?, 'short'::bytea, 'x', now(),"
            + " now() + interval '1 minute')");
  }

  @Test
  void onlyTheHashOfTheKeyIsStored() throws SQLException {
    var client = TestClients.register("persist-hash");
    try (var connection = dataSource.getConnection();
        var statement =
            connection.prepareStatement(
                "SELECT key_hash, clients::text FROM clients WHERE id = ?")) {
      statement.setObject(1, client.id());
      try (var row = statement.executeQuery()) {
        assertTrue(row.next());
        assertArrayEquals(ApiKeys.hash(client.clientKey()), row.getBytes(1));
        var secret = client.clientKey().substring(39);
        assertTrue(!row.getString(2).contains(secret), "the secret is not stored");
      }
    }
  }

  @Test
  void aPushTargetIsAllOrNothing() {
    assertRejected(
        "INSERT INTO clients (id, name, key_hash, created_at, push_provider)"
            + " VALUES (?, 'x', decode(repeat('00', 32), 'hex'), now(), 'fcm')");
    assertRejected(
        "INSERT INTO clients (id, name, key_hash, created_at, push_provider, push_token)"
            + " VALUES (?, 'x', decode(repeat('00', 32), 'hex'), now(), 'fcm', 't')");
  }

  @Test
  void aRevokedClientHasNoPushTarget() {
    assertRejected(
        "INSERT INTO clients"
            + " (id, name, key_hash, created_at, revoked_at, push_provider, push_token,"
            + " push_updated_at)"
            + " VALUES (?, 'x', decode(repeat('00', 32), 'hex'), now(), now(), 'fcm', 't', now())");
  }

  @Test
  void pushPreferencesHoldOnlyKnownValues() {
    var insert =
        "INSERT INTO clients (id, name, key_hash, created_at, %s)"
            + " VALUES (?, 'x', decode(repeat('00', 32), 'hex'), now(), %s)";
    assertRejected(insert.formatted("push_minimum_severity", "'URGENT'"));
    assertRejected(insert.formatted("push_muted_categories", "ARRAY['NEWS']"));
    assertRejected(insert.formatted("push_muted_categories", "ARRAY[NULL]::text[]"));
    assertRejected(insert.formatted("push_muted_producers", "ARRAY[NULL]::uuid[]"));
    assertRejected(
        insert.formatted(
            "push_muted_producers",
            "ARRAY(SELECT gen_random_uuid() FROM generate_series(1, 101))"));
  }

  @Test
  void pushResultsAreCompleteAndKnown() {
    var insert =
        "INSERT INTO clients (id, name, key_hash, created_at, %s)"
            + " VALUES (?, 'x', decode(repeat('00', 32), 'hex'), now(), %s)";
    assertRejected(insert.formatted("last_push_succeeded_at", "now()"));
    assertRejected(insert.formatted("last_push_succeeded_event_id", "gen_random_uuid()"));
    assertRejected(
        insert.formatted(
            "last_push_failed_at, last_push_failed_event_id", "now(), gen_random_uuid()"));
    assertRejected(insert.formatted("last_push_failed_result", "'PERMANENT_FAILURE'"));
    assertRejected(
        insert.formatted(
            "last_push_failed_at, last_push_failed_event_id, last_push_failed_result",
            "now(), gen_random_uuid(), 'DELIVERED'"));
  }

  @Test
  void keyHashesAre32Bytes() {
    assertRejected(
        "INSERT INTO clients (id, name, key_hash, created_at)"
            + " VALUES (?, 'x', decode('00', 'hex'), now())");
  }

  private void assertRejected(String insert) {
    var e =
        assertThrows(
            SQLException.class,
            () -> {
              try (var connection = dataSource.getConnection();
                  var statement = connection.prepareStatement(insert)) {
                statement.setObject(1, UUID.randomUUID());
                statement.executeUpdate();
              }
            });
    assertEquals("23514", e.getSQLState(), e.getMessage());
  }

  private Map<String, String> columnsOf(String table) throws SQLException {
    var columns = new LinkedHashMap<String, String>();
    try (var connection = dataSource.getConnection();
        var statement =
            connection.prepareStatement(
                "SELECT column_name, data_type, is_nullable FROM information_schema.columns"
                    + " WHERE table_name = ? ORDER BY ordinal_position")) {
      statement.setString(1, table);
      try (var rows = statement.executeQuery()) {
        while (rows.next()) {
          columns.put(rows.getString(1), rows.getString(2) + " " + rows.getString(3));
        }
      }
    }
    return columns;
  }
}
