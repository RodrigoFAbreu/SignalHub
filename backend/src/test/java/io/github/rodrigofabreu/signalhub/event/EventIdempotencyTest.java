package io.github.rodrigofabreu.signalhub.event;

import static io.github.rodrigofabreu.signalhub.event.EventApiTest.EVENTS;
import static io.github.rodrigofabreu.signalhub.event.EventApiTest.FULL_EVENT;
import static io.github.rodrigofabreu.signalhub.event.EventApiTest.MINIMAL_EVENT;
import static org.hamcrest.Matchers.endsWith;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.notNullValue;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.agroal.api.AgroalDataSource;
import io.github.rodrigofabreu.signalhub.TestClients;
import io.github.rodrigofabreu.signalhub.TestProducers;
import io.micrometer.core.instrument.MeterRegistry;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import io.restassured.response.ValidatableResponse;
import jakarta.inject.Inject;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/** Idempotent publishing with the {@code Idempotency-Key} header, against real PostgreSQL. */
@QuarkusTest
class EventIdempotencyTest {

  @Inject AgroalDataSource dataSource;
  @Inject MeterRegistry registry;

  private TestProducers.Registered producer;

  @BeforeEach
  void registerProducer() {
    producer = TestProducers.register("idempotency");
  }

  @Test
  void sendingTheSameEventAgainReturnsTheStoredOneWithoutStoringAnother() throws SQLException {
    var published = published();
    var first = post(producer, "run-1842", FULL_EVENT).statusCode(201).extract();
    var id = first.path("id");

    var repeated =
        post(producer, "run-1842", FULL_EVENT)
            .statusCode(200)
            .contentType(ContentType.JSON)
            .header("Location", endsWith(EVENTS + "/" + id))
            .extract();

    assertEquals(first.jsonPath().getMap(""), repeated.jsonPath().getMap(""));

    assertEquals(1, events(producer));
    assertEquals(1, count("push_dispatches WHERE event_id = '" + id + "'"));
    assertEquals(published + 1, published());
  }

  @Test
  void aRepeatReturnsTheEventAsItIsStoredNow() {
    String id = post(producer, "read-later", MINIMAL_EVENT).statusCode(201).extract().path("id");
    TestClients.asClient(TestClients.register("idempotency").clientKey())
        .put(EVENTS + "/" + id + "/read")
        .then()
        .statusCode(200);

    post(producer, "read-later", MINIMAL_EVENT)
        .statusCode(200)
        .body("id", equalTo(id))
        .body("readAt", notNullValue());
  }

  @Test
  void aKeyUsedForADifferentEventIsRefused() throws SQLException {
    post(producer, "reused", MINIMAL_EVENT).statusCode(201);

    post(producer, "reused", MINIMAL_EVENT.replace("Backup done", "Backup failed"))
        .statusCode(422)
        .contentType(ContentType.JSON)
        .body("title", equalTo("Idempotency key already used"))
        .body("status", equalTo(422))
        .body("violations[0].field", equalTo("Idempotency-Key"))
        .body("violations[0].message", equalTo("was already used for a different event"));

    assertEquals(1, events(producer));
  }

  @ParameterizedTest
  @ValueSource(
      strings = {
        "{\"category\": \"INFO\", \"severity\": \"LOW\", \"title\": \"Backup done\"}",
        "{\"category\": \"COMPLETED\", \"severity\": \"NORMAL\", \"title\": \"Backup done\"}",
        "{\"category\": \"COMPLETED\", \"severity\": \"LOW\", \"title\": \"Backup done\","
            + " \"context\": \"nas\"}",
        "{\"category\": \"COMPLETED\", \"severity\": \"LOW\", \"title\": \"Backup done\","
            + " \"message\": \"\"}",
        "{\"category\": \"COMPLETED\", \"severity\": \"LOW\", \"title\": \"Backup done\","
            + " \"metadata\": {\"a\": 1}}",
        "{\"category\": \"COMPLETED\", \"severity\": \"LOW\", \"title\": \"Backup done\","
            + " \"occurredAt\": \"2026-09-25T14:03:00Z\"}"
      })
  void everyFieldTakesPartInTheComparison(String different) {
    post(producer, "compare", MINIMAL_EVENT).statusCode(201);

    post(producer, "compare", different).statusCode(422);
  }

  @Test
  void theSameEventWrittenDifferentlyIsTheSameEvent() {
    var event =
        """
        {"category": "COMPLETED", "severity": "LOW", "title": "Backup done",
         "metadata": {"a": 1.10, "b": {"c": [1, 2]}},
         "occurredAt": "2026-09-25T14:03:00.1234567+02:00"}
        """;
    var rewritten =
        """
        {"occurredAt": "2026-09-25T12:03:00.123456Z", "title": "Backup done",
         "metadata": {"b": {"c": [1, 2]}, "a": 1.1}, "severity": "LOW", "category": "COMPLETED"}
        """;
    String id = post(producer, "rewritten", event).statusCode(201).extract().path("id");

    post(producer, "rewritten", rewritten).statusCode(200).body("id", equalTo(id));
  }

  @Test
  void keysBelongToTheirProducer() throws SQLException {
    var other = TestProducers.register("idempotency-other");
    String first = post(producer, "shared", MINIMAL_EVENT).statusCode(201).extract().path("id");

    String second = post(other, "shared", MINIMAL_EVENT).statusCode(201).extract().path("id");

    assertNotEquals(first, second);
    assertEquals(1, events(producer));
    assertEquals(1, events(other));
  }

  @Test
  void withoutAKeyOrWithAnotherKeyEveryRequestStoresAnEvent() throws SQLException {
    post(producer, null, MINIMAL_EVENT).statusCode(201);
    post(producer, null, MINIMAL_EVENT).statusCode(201);
    post(producer, "one", MINIMAL_EVENT).statusCode(201);
    post(producer, "two", MINIMAL_EVENT).statusCode(201);

    assertEquals(4, events(producer));
  }

  @Test
  void anEmptyKeyIsNoKey() throws SQLException {
    post(producer, "", MINIMAL_EVENT).statusCode(201);
    post(producer, "", MINIMAL_EVENT).statusCode(201);

    assertEquals(2, events(producer));
  }

  @Test
  void keysAreUpTo200VisibleAsciiCharacters() {
    post(producer, "!~" + "k".repeat(198), MINIMAL_EVENT).statusCode(201);
    post(producer, UUID.randomUUID().toString(), MINIMAL_EVENT).statusCode(201);
  }

  @ParameterizedTest
  @ValueSource(strings = {"two words", "tab\tkey", "café"})
  void malformedKeysAreRejected(String key) throws SQLException {
    post(producer, key, MINIMAL_EVENT)
        .statusCode(400)
        .body("violations[0].field", equalTo("Idempotency-Key"))
        .body(
            "violations[0].message",
            equalTo("must be 1 to 200 visible ASCII characters, without spaces"));

    assertEquals(0, events(producer));
  }

  @Test
  void aKeyLongerThan200CharactersIsRejected() {
    post(producer, "k".repeat(201), MINIMAL_EVENT).statusCode(400);
  }

  @Test
  void authenticationComesFirst() {
    TestProducers.asProducer(producer.apiKey() + "x")
        .header("Idempotency-Key", "")
        .contentType(ContentType.JSON)
        .body(MINIMAL_EVENT)
        .post(EVENTS)
        .then()
        .statusCode(401);
  }

  @Test
  void concurrentRequestsWithOneKeyStoreOneEvent() throws Exception {
    var requests = 8;
    var statuses = new ArrayList<Integer>();
    var ids = new ArrayList<String>();
    try (var pool = Executors.newFixedThreadPool(requests)) {
      var answers = new ArrayList<Future<ValidatableResponse>>();
      for (var i = 0; i < requests; i++) {
        Callable<ValidatableResponse> send = () -> post(producer, "concurrent", MINIMAL_EVENT);
        answers.add(pool.submit(send));
      }
      for (var answer : answers) {
        var response = answer.get().extract();
        statuses.add(response.statusCode());
        ids.add(response.path("id"));
      }
    }

    assertEquals(1, statuses.stream().filter(status -> status == 201).count());
    assertEquals(requests - 1, statuses.stream().filter(status -> status == 200).count());
    assertEquals(1, ids.stream().distinct().count());
    assertEquals(1, events(producer));
  }

  @Test
  void deletingTheEventFreesItsKey() throws SQLException {
    String first = post(producer, "retained", MINIMAL_EVENT).statusCode(201).extract().path("id");
    execute("DELETE FROM events WHERE id = '" + first + "'");

    String second = post(producer, "retained", MINIMAL_EVENT).statusCode(201).extract().path("id");

    assertNotEquals(first, second);
  }

  @Test
  void theDatabaseKeepsKeysUniquePerProducer() throws SQLException {
    post(producer, "unique", MINIMAL_EVENT).statusCode(201);

    var copy =
        "INSERT INTO events (id, producer_id, category, severity, title, metadata, created_at,"
            + " idempotency_key) SELECT gen_random_uuid(), producer_id, category, severity, title,"
            + " metadata, created_at, idempotency_key FROM events WHERE producer_id = '"
            + producer.id()
            + "'";
    var error = assertThrows(SQLException.class, () -> execute(copy));
    assertEquals("23505", error.getSQLState());
  }

  private static ValidatableResponse post(
      TestProducers.Registered producer, String idempotencyKey, String body) {
    var request = TestProducers.asProducer(producer.apiKey()).contentType(ContentType.JSON);
    if (idempotencyKey != null) {
      request.header("Idempotency-Key", idempotencyKey);
    }
    return request.body(body).when().post(EVENTS).then();
  }

  private double published() {
    return registry.get("signalhub.events.published").counter().count();
  }

  private long events(TestProducers.Registered producer) throws SQLException {
    return count("events WHERE producer_id = '" + producer.id() + "'");
  }

  private long count(String from) throws SQLException {
    try (var connection = dataSource.getConnection();
        var statement = connection.prepareStatement("SELECT count(*) FROM " + from);
        var rows = statement.executeQuery()) {
      assertTrue(rows.next());
      return rows.getLong(1);
    }
  }

  private void execute(String sql) throws SQLException {
    try (var connection = dataSource.getConnection();
        var statement = connection.prepareStatement(sql)) {
      statement.executeUpdate();
    }
  }
}
