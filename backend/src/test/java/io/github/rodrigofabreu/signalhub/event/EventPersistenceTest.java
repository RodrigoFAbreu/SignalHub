package io.github.rodrigofabreu.signalhub.event;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.agroal.api.AgroalDataSource;
import io.github.rodrigofabreu.signalhub.TestProducers;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import jakarta.inject.Inject;
import java.sql.SQLException;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.MigrationState;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

/** What the API writes to PostgreSQL, and the invariants the schema enforces on its own. */
@QuarkusTest
class EventPersistenceTest {

  /** PostgreSQL's SQLSTATE for a violated check constraint. */
  private static final String CHECK_VIOLATION = "23514";

  /** PostgreSQL's SQLSTATE for a violated foreign key. */
  private static final String FOREIGN_KEY_VIOLATION = "23503";

  /** Owner of the rows this test inserts directly. */
  private static final String PRODUCER =
      "(SELECT id FROM producers WHERE name = 'persistence-test')";

  private static TestProducers.Registered producer;

  @Inject AgroalDataSource dataSource;
  @Inject Flyway flyway;
  @Inject ObjectMapper json;

  @BeforeEach
  void registerProducers() throws SQLException {
    if (producer == null) {
      producer = TestProducers.register("event-persistence-test");
    }
    try (var connection = dataSource.getConnection();
        var statement = connection.createStatement()) {
      statement.executeUpdate(
          "INSERT INTO producers (id, name, created_at)"
              + " VALUES (gen_random_uuid(), 'persistence-test', now())"
              + " ON CONFLICT (name) DO NOTHING");
    }
  }

  @Test
  void migrationCreatesTheEventsTable() throws SQLException {
    var v1 =
        Arrays.stream(flyway.info().applied())
            .filter(m -> "1".equals(m.getVersion().getVersion()))
            .findFirst()
            .orElseThrow();
    assertEquals("create events", v1.getDescription());
    assertEquals(MigrationState.SUCCESS, v1.getState());

    var expected = new LinkedHashMap<String, String>();
    expected.put("id", "uuid NO");
    expected.put("context", "text YES");
    expected.put("category", "text NO");
    expected.put("severity", "text NO");
    expected.put("title", "text NO");
    expected.put("message", "text YES");
    expected.put("metadata", "jsonb NO");
    expected.put("occurred_at", "timestamp with time zone YES");
    expected.put("created_at", "timestamp with time zone NO");
    // Added by V2, replacing the producer-supplied source.
    expected.put("producer_id", "uuid NO");
    // Added by V6: null while the event is unread.
    expected.put("read_at", "timestamp with time zone YES");
    // Added by V9: null when the producer sent no Idempotency-Key.
    expected.put("idempotency_key", "text YES");
    assertEquals(expected, columnsOf("events"));
  }

  @Test
  void createdEventIsStoredInPostgres() throws Exception {
    String id =
        TestProducers.asProducer(producer.apiKey())
            .contentType(ContentType.JSON)
            .body(EventApiTest.FULL_EVENT)
            .when()
            .post(EventApiTest.EVENTS)
            .then()
            .statusCode(201)
            .extract()
            .path("id");

    try (var connection = dataSource.getConnection();
        var statement =
            connection.prepareStatement(
                "SELECT producer_id, context, category, severity, title, message, metadata::text,"
                    + " occurred_at, created_at FROM events WHERE id = ?")) {
      statement.setObject(1, UUID.fromString(id));
      try (var row = statement.executeQuery()) {
        assertTrue(row.next(), "event " + id + " must be in the database");
        assertEquals(producer.id(), row.getObject("producer_id", UUID.class));
        assertEquals("signalhub", row.getString("context"));
        assertEquals("BLOCKED", row.getString("category"));
        assertEquals("HIGH", row.getString("severity"));
        assertEquals("Nightly build failed", row.getString("title"));
        assertEquals("3 of 412 tests failed on main.", row.getString("message"));
        assertEquals(
            json.readTree("{\"pipeline\": \"nightly\", \"run\": 1842}"),
            json.readTree(row.getString(7)));
        assertEquals(
            OffsetDateTime.of(2026, 9, 25, 12, 3, 0, 0, ZoneOffset.UTC).toInstant(),
            row.getObject("occurred_at", OffsetDateTime.class).toInstant());
        assertTrue(row.getObject("created_at", OffsetDateTime.class) != null);
      }
    }
  }

  @Test
  void absentMetadataIsStoredAsAnEmptyObject() throws SQLException {
    String id =
        TestProducers.asProducer(producer.apiKey())
            .contentType(ContentType.JSON)
            .body(EventApiTest.MINIMAL_EVENT)
            .when()
            .post(EventApiTest.EVENTS)
            .then()
            .statusCode(201)
            .extract()
            .path("id");

    try (var connection = dataSource.getConnection();
        var statement =
            connection.prepareStatement(
                "SELECT metadata::text, context, occurred_at FROM events WHERE id = ?")) {
      statement.setObject(1, UUID.fromString(id));
      try (var row = statement.executeQuery()) {
        assertTrue(row.next());
        assertEquals("{}", row.getString(1));
        assertNull(row.getString(2));
        assertNull(row.getObject(3));
      }
    }
  }

  @Test
  void validRowIsAccepted() throws SQLException {
    insert(validRow());
  }

  @ParameterizedTest(name = "{0} = {1}")
  @CsvSource(
      delimiter = '|',
      quoteCharacter = '`',
      value = {
        "context  | ''",
        "category | 'URGENT'",
        "category | 'info'",
        "severity | 'MEDIUM'",
        "title    | '   '",
        "title    | repeat('t', 201)",
        "message  | repeat('m', 4001)",
        "metadata | '[1, 2]'::jsonb",
        "metadata | '\"text\"'::jsonb",
      })
  void checkConstraintsRejectInvalidRows(String column, String value) {
    var row = validRow();
    row.put(column, value);

    var error = assertThrows(SQLException.class, () -> insert(row));
    assertEquals(CHECK_VIOLATION, error.getSQLState(), error.getMessage());
  }

  @ParameterizedTest
  @CsvSource({"producer_id", "category", "severity", "title", "metadata", "created_at"})
  void requiredColumnsAreNotNull(String column) {
    var row = validRow();
    row.put(column, "NULL");

    var error = assertThrows(SQLException.class, () -> insert(row));
    assertEquals("23502", error.getSQLState(), error.getMessage());
  }

  @Test
  void producerMustExist() {
    var row = validRow();
    row.put("producer_id", "gen_random_uuid()");

    var error = assertThrows(SQLException.class, () -> insert(row));
    assertEquals(FOREIGN_KEY_VIOLATION, error.getSQLState(), error.getMessage());
  }

  private static Map<String, String> validRow() {
    var row = new LinkedHashMap<String, String>();
    row.put("id", "gen_random_uuid()");
    row.put("producer_id", PRODUCER);
    row.put("context", "NULL");
    row.put("category", "'INFO'");
    row.put("severity", "'NORMAL'");
    row.put("title", "'title'");
    row.put("message", "NULL");
    row.put("metadata", "'{}'::jsonb");
    row.put("occurred_at", "NULL");
    row.put("created_at", "now()");
    return row;
  }

  /** Inserts SQL expressions directly, bypassing the application's validation. */
  private void insert(Map<String, String> row) throws SQLException {
    var sql =
        "INSERT INTO events ("
            + String.join(", ", row.keySet())
            + ") VALUES ("
            + String.join(", ", row.values())
            + ")";
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
