package io.github.rodrigofabreu.signalhub.event;

import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.github.rodrigofabreu.signalhub.TestProducers.asProducer;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.nullValue;
import static org.junit.jupiter.api.Assertions.assertEquals;

import io.agroal.api.AgroalDataSource;
import io.github.rodrigofabreu.signalhub.TestClients;
import io.github.rodrigofabreu.signalhub.TestProducers;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import io.restassured.response.ValidatableResponse;
import io.restassured.specification.RequestSpecification;
import jakarta.inject.Inject;
import java.sql.SQLException;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.IntStream;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/**
 * Deleting events with the admin token, against real PostgreSQL: one event, a selection, a
 * producer's events and events older than a time, each bulk delete with its dry run; what goes with
 * an event and what stays.
 */
@QuarkusTest
class EventDeletionApiTest {

  private static final String EVENTS = "/api/v1/events";
  private static final String ADMIN_EVENTS = "/api/v1/admin/events";
  private static final String DELETE_EVENTS = ADMIN_EVENTS + "/delete";

  @Inject AgroalDataSource dataSource;

  @Test
  void deletingAnEventRemovesItsPushAndRetriesButNotItsProducerClientsOrOtherEvents()
      throws SQLException {
    var producer = TestProducers.register("delete-one");
    var client = TestClients.register("delete-one-client");
    var deleted = publish(producer);
    var kept = publish(producer);
    retry(deleted, client.id());
    retry(kept, client.id());
    assertEquals(1, count("push_dispatches", deleted));

    asAdmin().delete(ADMIN_EVENTS + "/" + deleted).then().statusCode(204);

    asAdmin().get(EVENTS + "/" + deleted).then().statusCode(404);
    assertEquals(0, count("push_dispatches", deleted));
    assertEquals(0, count("push_retries", deleted));
    asAdmin().get(EVENTS + "/" + kept).then().statusCode(200);
    assertEquals(1, count("push_dispatches", kept));
    assertEquals(1, count("push_retries", kept));
    asAdmin().get(TestProducers.ADMIN + "/" + producer.id()).then().statusCode(200);
    asClient(client.clientKey()).get(TestClients.CLIENT).then().statusCode(200);
  }

  @Test
  void anUnknownOrDeletedEventIsNotFound() {
    var event = publish(TestProducers.register("delete-twice"));
    asAdmin().delete(ADMIN_EVENTS + "/" + event).then().statusCode(204);

    for (var id : List.of(event, UUID.randomUUID())) {
      asAdmin()
          .delete(ADMIN_EVENTS + "/" + id)
          .then()
          .statusCode(404)
          .body("title", equalTo("Event not found"))
          .body("status", equalTo(404));
    }
    asAdmin().delete(ADMIN_EVENTS + "/not-a-uuid").then().statusCode(404);
  }

  @Test
  void aSelectionIsCountedByADryRunThenDeletedSkippingUnknownIds() {
    var producer = TestProducers.register("delete-selection");
    var first = publish(producer);
    var second = publish(producer);
    var kept = publish(producer);
    var selection = List.of(first.toString(), second.toString(), UUID.randomUUID().toString());

    deleteEvents(Map.of("ids", selection, "dryRun", true))
        .statusCode(200)
        .body("count", equalTo(2))
        .body("dryRun", equalTo(true));
    asAdmin().get(EVENTS + "/" + first).then().statusCode(200);

    deleteEvents(Map.of("ids", selection))
        .statusCode(200)
        .body("count", equalTo(2))
        .body("dryRun", equalTo(false));

    asAdmin().get(EVENTS + "/" + first).then().statusCode(404);
    asAdmin().get(EVENTS + "/" + second).then().statusCode(404);
    asAdmin().get(EVENTS + "/" + kept).then().statusCode(200);
    deleteEvents(Map.of("ids", selection)).statusCode(200).body("count", equalTo(0));
  }

  @Test
  void everyEventOfAProducerIsDeletedAndTheProducerStays() throws SQLException {
    var producer = TestProducers.register("delete-producer");
    var other = TestProducers.register("delete-producer-other");
    var client = TestClients.register("delete-producer-client");
    var events = List.of(publish(producer), publish(producer));
    retry(events.get(0), client.id());
    var kept = publish(other);
    var filter = Map.<String, Object>of("producerId", producer.id().toString());

    deleteEvents(withDryRun(filter)).statusCode(200).body("count", equalTo(2));
    listOf(producer.id()).body("items", hasSize(2));

    deleteEvents(filter).statusCode(200).body("count", equalTo(2)).body("dryRun", equalTo(false));

    listOf(producer.id()).body("items", hasSize(0));
    for (var event : events) {
      assertEquals(0, count("push_dispatches", event));
      assertEquals(0, count("push_retries", event));
    }
    asAdmin()
        .get(TestProducers.ADMIN + "/" + producer.id())
        .then()
        .statusCode(200)
        .body("lastEventAt", nullValue());
    asAdmin().get(EVENTS + "/" + kept).then().statusCode(200);
    // The producer keeps publishing with its key.
    publish(producer);
  }

  @Test
  void everyEventOlderThanATimeIsDeleted() throws SQLException {
    // Far in the past, so no other test's events are older than the cutoff.
    var producer = TestProducers.register("delete-older");
    var older = insertEvent(producer.id(), Instant.parse("1990-01-01T00:00:00Z"));
    var atCutoff = insertEvent(producer.id(), Instant.parse("1990-01-15T00:00:00Z"));
    var filter = Map.<String, Object>of("createdBefore", "1990-01-15T01:00:00+01:00");

    deleteEvents(withDryRun(filter)).statusCode(200).body("count", equalTo(1));
    asAdmin().get(EVENTS + "/" + older).then().statusCode(200);

    deleteEvents(filter).statusCode(200).body("count", equalTo(1));

    asAdmin().get(EVENTS + "/" + older).then().statusCode(404);
    // Before is exclusive: an event created at the cutoff stays.
    asAdmin().get(EVENTS + "/" + atCutoff).then().statusCode(200);
    asAdmin().delete(ADMIN_EVENTS + "/" + atCutoff).then().statusCode(204);
  }

  @Test
  void aProducerAndATimeMustBothMatch() throws SQLException {
    var producer = TestProducers.register("delete-both");
    var other = TestProducers.register("delete-both-other");
    var old = insertEvent(producer.id(), Instant.parse("1991-01-01T00:00:00Z"));
    var othersOld = insertEvent(other.id(), Instant.parse("1991-01-01T00:00:00Z"));
    var recent = publish(producer);
    var filter =
        Map.<String, Object>of(
            "producerId", producer.id().toString(), "createdBefore", "1992-01-01T00:00:00Z");

    deleteEvents(withDryRun(filter)).statusCode(200).body("count", equalTo(1));
    deleteEvents(filter).statusCode(200).body("count", equalTo(1));

    asAdmin().get(EVENTS + "/" + old).then().statusCode(404);
    asAdmin().get(EVENTS + "/" + othersOld).then().statusCode(200);
    asAdmin().get(EVENTS + "/" + recent).then().statusCode(200);
    asAdmin().delete(ADMIN_EVENTS + "/" + othersOld).then().statusCode(204);
  }

  @Test
  void anUnknownProducerIsNotFound() {
    var filter = Map.<String, Object>of("producerId", UUID.randomUUID().toString());
    for (var request : List.of(filter, withDryRun(filter))) {
      deleteEvents(request)
          .statusCode(404)
          .body("title", equalTo("Producer not found"))
          .body("status", equalTo(404));
    }
  }

  @ParameterizedTest
  @ValueSource(
      strings = {
        "{}",
        "{\"dryRun\": true}",
        "{\"ids\": []}",
        "{\"ids\": [null]}",
        "{\"ids\": [\"not-a-uuid\"]}",
        "{\"ids\": [\"01997d5e-8a3c-7b1e-9f2a-4c6d8e0f1a2b\"], \"producerId\":"
            + " \"01997d5e-8a3c-7b1e-9f2a-4c6d8e0f1a2b\"}",
        "{\"ids\": [\"01997d5e-8a3c-7b1e-9f2a-4c6d8e0f1a2b\"], \"createdBefore\":"
            + " \"2000-01-01T00:00:00Z\"}",
        "{\"createdBefore\": \"2000-01-01T00:00:00\"}",
        "{\"createdBefore\": \"+10000-01-01T00:00:00Z\"}",
        "{\"producerId\": \"01997d5e-8a3c-7b1e-9f2a-4c6d8e0f1a2b\", \"dryRun\": \"true\"}",
        "{\"producerId\": \"01997d5e-8a3c-7b1e-9f2a-4c6d8e0f1a2b\", \"everything\": true}",
        "null"
      })
  void anInvalidRequestIsRefusedAndDeletesNothing(String body) {
    var event = publish(TestProducers.register("delete-invalid"));

    asAdmin()
        .contentType(ContentType.JSON)
        .body(body)
        .post(DELETE_EVENTS)
        .then()
        .statusCode(400)
        .body("status", equalTo(400));

    asAdmin().get(EVENTS + "/" + event).then().statusCode(200);
  }

  @Test
  void aSelectionHoldsAtMostOneHundredEvents() {
    var ids = IntStream.range(0, 101).mapToObj(i -> UUID.randomUUID().toString()).toList();
    deleteEvents(Map.of("ids", ids, "dryRun", true)).statusCode(400);
    deleteEvents(Map.of("ids", ids.subList(0, 100), "dryRun", true))
        .statusCode(200)
        .body("count", equalTo(0));
  }

  @Test
  void deletingRequiresTheAdminToken() {
    var producer = TestProducers.register("delete-unauthorized");
    var client = TestClients.register("delete-unauthorized-client");
    var event = publish(producer);
    for (var credential : credentials(producer, client)) {
      credential.delete(ADMIN_EVENTS + "/" + event).then().statusCode(401);
    }
    for (var credential : credentials(producer, client)) {
      credential
          .contentType(ContentType.JSON)
          .body(Map.of("ids", List.of(event.toString())))
          .post(DELETE_EVENTS)
          .then()
          .statusCode(401);
    }

    asAdmin().get(EVENTS + "/" + event).then().statusCode(200);
  }

  /** Every credential but the admin token, each for one request. */
  private static List<RequestSpecification> credentials(
      TestProducers.Registered producer, TestClients.Registered client) {
    return List.of(
        given(),
        given().header("Authorization", "Bearer wrong-admin-token-0123456789abcdef"),
        asProducer(producer.apiKey()),
        asClient(client.clientKey()));
  }

  private static Map<String, Object> withDryRun(Map<String, Object> filter) {
    var request = new HashMap<>(filter);
    request.put("dryRun", true);
    return Collections.unmodifiableMap(request);
  }

  private static ValidatableResponse deleteEvents(Map<String, ?> request) {
    return asAdmin().contentType(ContentType.JSON).body(request).post(DELETE_EVENTS).then();
  }

  private static ValidatableResponse listOf(UUID producerId) {
    return asAdmin().queryParam("producerId", producerId.toString()).get(EVENTS).then();
  }

  private static UUID publish(TestProducers.Registered producer) {
    return UUID.fromString(
        asProducer(producer.apiKey())
            .contentType(ContentType.JSON)
            .body(Map.of("category", "INFO", "severity", "LOW", "title", "To delete"))
            .post(EVENTS)
            .then()
            .statusCode(201)
            .extract()
            .path("id"));
  }

  private UUID insertEvent(UUID producerId, Instant createdAt) throws SQLException {
    var id = UUID.randomUUID();
    execute(
        "INSERT INTO events (id, producer_id, category, severity, title, metadata, created_at)"
            + " VALUES (?, ?, 'INFO', 'LOW', 'Old', '{}', ?)",
        id,
        producerId,
        createdAt.atOffset(ZoneOffset.UTC));
    return id;
  }

  private void retry(UUID eventId, UUID clientId) throws SQLException {
    execute(
        "INSERT INTO push_retries (event_id, client_id, attempts, next_attempt_at)"
            + " VALUES (?, ?, 1, now() + interval '1 hour')",
        eventId,
        clientId);
  }

  private void execute(String sql, Object... parameters) throws SQLException {
    try (var connection = dataSource.getConnection();
        var statement = connection.prepareStatement(sql)) {
      for (var i = 0; i < parameters.length; i++) {
        statement.setObject(i + 1, parameters[i]);
      }
      statement.executeUpdate();
    }
  }

  private long count(String table, UUID eventId) throws SQLException {
    try (var connection = dataSource.getConnection();
        var statement =
            connection.prepareStatement("SELECT count(*) FROM " + table + " WHERE event_id = ?")) {
      statement.setObject(1, eventId);
      try (var rows = statement.executeQuery()) {
        rows.next();
        return rows.getLong(1);
      }
    }
  }
}
