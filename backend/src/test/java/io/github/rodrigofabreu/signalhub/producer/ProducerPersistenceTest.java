package io.github.rodrigofabreu.signalhub.producer;

import static io.github.rodrigofabreu.signalhub.TestProducers.ADMIN;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.github.rodrigofabreu.signalhub.TestProducers.asProducer;
import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.agroal.api.AgroalDataSource;
import io.github.rodrigofabreu.signalhub.TestProducers;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import jakarta.inject.Inject;
import java.sql.SQLException;
import java.util.Arrays;
import java.util.Base64;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.Map;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.MigrationState;
import org.junit.jupiter.api.Test;

/** What producer registration writes to PostgreSQL: hashes only, never keys. */
@QuarkusTest
class ProducerPersistenceTest {

  @Inject AgroalDataSource dataSource;
  @Inject Flyway flyway;

  @Test
  void migrationCreatesTheProducerTables() throws SQLException {
    var v2 =
        Arrays.stream(flyway.info().applied())
            .filter(m -> "2".equals(m.getVersion().getVersion()))
            .findFirst()
            .orElseThrow();
    assertEquals("add producer authentication", v2.getDescription());
    assertEquals(MigrationState.SUCCESS, v2.getState());

    var producers = new LinkedHashMap<String, String>();
    producers.put("id", "uuid NO");
    producers.put("name", "text NO");
    producers.put("created_at", "timestamp with time zone NO");
    producers.put("disabled_at", "timestamp with time zone YES");
    assertEquals(producers, columnsOf("producers"));

    var keys = new LinkedHashMap<String, String>();
    keys.put("id", "uuid NO");
    keys.put("producer_id", "uuid NO");
    keys.put("key_hash", "bytea NO");
    keys.put("created_at", "timestamp with time zone NO");
    keys.put("revoked_at", "timestamp with time zone YES");
    assertEquals(keys, columnsOf("producer_api_keys"));
  }

  @Test
  void onlyTheHashOfAKeyIsStored() throws SQLException {
    var producer = TestProducers.register("persist-hash");

    try (var connection = dataSource.getConnection();
        var statement =
            connection.prepareStatement("SELECT key_hash FROM producer_api_keys WHERE id = ?")) {
      statement.setObject(1, producer.keyId());
      try (var row = statement.executeQuery()) {
        assertTrue(row.next());
        assertArrayEquals(ApiKeys.hash(producer.apiKey()), row.getBytes(1));
      }
    }
  }

  @Test
  void noKeyOrSecretAppearsAnywhereInTheDatabase() throws SQLException {
    var producer = TestProducers.register("persist-no-plaintext");
    var rotated =
        asAdmin()
            .post(ADMIN + "/" + producer.id() + "/keys")
            .then()
            .statusCode(201)
            .extract()
            .<String>path("apiKey");
    asProducer(rotated)
        .contentType(ContentType.JSON)
        .body("{\"category\": \"INFO\", \"severity\": \"LOW\", \"title\": \"stored\"}")
        .post("/api/v1/events")
        .then()
        .statusCode(201);

    var database = dumpDatabase();
    for (var key : new String[] {producer.apiKey(), rotated}) {
      var secret = key.substring(39);
      var secretBytes = Base64.getUrlDecoder().decode(secret);
      assertFalse(database.contains(secret), "secret stored as text");
      assertFalse(database.contains(HexFormat.of().formatHex(secretBytes)), "secret stored as hex");
      assertFalse(database.contains(Base64.getEncoder().encodeToString(secretBytes)));
    }
  }

  @Test
  void keyHashMustBeA256BitHash() {
    var error =
        assertThrows(
            SQLException.class,
            () ->
                execute(
                    "INSERT INTO producer_api_keys (id, producer_id, key_hash, created_at)"
                        + " SELECT gen_random_uuid(), id, '\\x00'::bytea, now() FROM producers"
                        + " LIMIT 1"));
    assertEquals("23514", error.getSQLState(), error.getMessage());
  }

  @Test
  void producerNamesAreUnique() throws SQLException {
    execute(
        "INSERT INTO producers (id, name, created_at) VALUES (gen_random_uuid(), 'unique', now())");
    var error =
        assertThrows(
            SQLException.class,
            () ->
                execute(
                    "INSERT INTO producers (id, name, created_at)"
                        + " VALUES (gen_random_uuid(), 'unique', now())"));
    assertEquals("23505", error.getSQLState(), error.getMessage());
  }

  /** Every row of every application table, as text, including bytea columns as hex. */
  private String dumpDatabase() throws SQLException {
    var dump = new StringBuilder();
    for (var table : new String[] {"producers", "producer_api_keys", "events"}) {
      try (var connection = dataSource.getConnection();
          var rows =
              connection.createStatement().executeQuery("SELECT t::text FROM " + table + " AS t")) {
        while (rows.next()) {
          dump.append(rows.getString(1)).append('\n');
        }
      }
    }
    return dump.toString();
  }

  private void execute(String sql) throws SQLException {
    try (var connection = dataSource.getConnection();
        var statement = connection.createStatement()) {
      statement.executeUpdate(sql);
    }
  }

  private Map<String, String> columnsOf(String table) throws SQLException {
    var columns = new LinkedHashMap<String, String>();
    try (var connection = dataSource.getConnection();
        var statement =
            connection.prepareStatement(
                "SELECT column_name, data_type, is_nullable FROM information_schema.columns"
                    + " WHERE table_schema = 'public' AND table_name = ? ORDER BY ordinal_position")) {
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
