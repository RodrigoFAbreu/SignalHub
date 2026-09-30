package io.github.rodrigofabreu.signalhub.event;

import static io.github.rodrigofabreu.signalhub.TestClients.ADMIN;
import static io.github.rodrigofabreu.signalhub.TestClients.CLIENT;
import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.github.rodrigofabreu.signalhub.TestProducers.asProducer;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.empty;
import static org.hamcrest.Matchers.equalTo;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.agroal.api.AgroalDataSource;
import io.github.rodrigofabreu.signalhub.TestClients;
import io.github.rodrigofabreu.signalhub.TestProducers;
import io.github.rodrigofabreu.signalhub.push.FakePushProvider;
import io.github.rodrigofabreu.signalhub.push.PushOutcome;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import jakarta.inject.Inject;
import java.sql.SQLException;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * An event's delivery records in the management API, written by the dispatcher on real PostgreSQL
 * with the fake provider. The scheduler is off in tests, so each test runs the dispatcher itself.
 * Clients of other tests are recorded too, so each test reads only its own clients' records.
 */
@QuarkusTest
class EventDeliveryApiTest {

  private static final String ADMIN_EVENTS = "/api/v1/admin/events";
  private static final PushOutcome TEMPORARY =
      new PushOutcome(PushOutcome.Status.TRANSIENT_FAILURE, "HTTP 503 UNAVAILABLE");

  // The push token each client of withPreferences was given.
  private static final Map<TestClients.Registered, String> TOKENS = new ConcurrentHashMap<>();

  @Inject EventPushDispatcher dispatcher;
  @Inject FakePushProvider fake;
  @Inject AgroalDataSource dataSource;

  private TestProducers.Registered producer;

  @BeforeEach
  void setUp() {
    // Events from other tests wait in the outbox too; send them before each test's own.
    dispatcher.dispatchPending();
    fake.answer((token, message) -> PushOutcome.delivered());
    producer = TestProducers.register("deliveries");
  }

  @Test
  void aDeliveredPushIsRecordedByTheDevicesNameWithoutItsToken() {
    var client = TestClients.register("delivered-phone");
    var token = "deliveries-" + UUID.randomUUID();
    setTarget(client, FakePushProvider.NAME, token);
    var before = Instant.now();
    var eventId = publish("NORMAL", "INFO");

    dispatcher.dispatchPending();

    var body = deliveries(eventId).extract();
    var records = recordsOf(body.jsonPath().getList("items"), client.id());
    assertEquals(1, records.size());
    var record = records.get(0);
    assertEquals("delivered-phone", record.get("clientName"));
    assertEquals(1, record.get("attempt"));
    assertEquals("DELIVERED", record.get("outcome"));
    assertNull(record.get("detail"));
    assertFalse(Instant.parse((String) record.get("at")).isBefore(before.minusSeconds(1)));
    assertFalse(body.asString().contains(token), "the push token is never returned");
  }

  @Test
  void eachPreferenceThatFiltersTheEventOutIsNamed() {
    var paused = withPreferences("paused", false, "LOW", List.of(), List.of());
    var severity = withPreferences("severity", true, "HIGH", List.of(), List.of());
    var category = withPreferences("category", true, "LOW", List.of("COMPLETED"), List.of());
    var muted = withPreferences("producer", true, "LOW", List.of(), List.of(producer.id()));
    var eventId = publish("NORMAL", "COMPLETED");

    dispatcher.dispatchPending();

    var items = deliveries(eventId).extract().jsonPath().<Map<String, Object>>getList("items");
    for (var expected :
        Map.of(
                paused, "pushes paused",
                severity, "below the minimum severity",
                category, "category muted",
                muted, "producer muted")
            .entrySet()) {
      var records = recordsOf(items, expected.getKey().id());
      assertEquals(1, records.size());
      assertEquals("FILTERED", records.get(0).get("outcome"));
      assertEquals(expected.getValue(), records.get(0).get("detail"));
    }
    var filteredTokens = List.of(paused, severity, category, muted).stream().map(TOKENS::get);
    assertTrue(
        filteredTokens.noneMatch(sentTo(eventId)::contains),
        "nothing was sent to a filtered device");
  }

  @Test
  void aDeviceWithoutAPushTargetIsRecordedButARevokedOneIsNot() {
    var noTarget = TestClients.register("no-target");
    var revoked = TestClients.register("revoked-before");
    setTarget(revoked, FakePushProvider.NAME, "deliveries-" + UUID.randomUUID());
    asAdmin().post(ADMIN + "/" + revoked.id() + "/revoke").then().statusCode(200);
    var eventId = publish("NORMAL", "INFO");

    dispatcher.dispatchPending();

    var items = deliveries(eventId).extract().jsonPath().<Map<String, Object>>getList("items");
    var records = recordsOf(items, noTarget.id());
    assertEquals(1, records.size());
    assertEquals("NO_TARGET", records.get(0).get("outcome"));
    assertNull(records.get(0).get("detail"));
    assertTrue(recordsOf(items, revoked.id()).isEmpty());
  }

  @Test
  void failuresAreRecordedWithTheProvidersReason() {
    var permanent = TestClients.register("permanent");
    var permanentToken = "deliveries-" + UUID.randomUUID();
    setTarget(permanent, FakePushProvider.NAME, permanentToken);
    var invalid = TestClients.register("invalid");
    var invalidToken = "deliveries-" + UUID.randomUUID();
    setTarget(invalid, FakePushProvider.NAME, invalidToken);
    var unsupported = TestClients.register("unsupported");
    setTarget(unsupported, "otherprovider", "deliveries-" + UUID.randomUUID());
    fake.answer(
        (to, message) -> {
          if (to.equals(permanentToken)) {
            return new PushOutcome(PushOutcome.Status.PERMANENT_FAILURE, "HTTP 400 SENDER_ID");
          }
          if (to.equals(invalidToken)) {
            return new PushOutcome(PushOutcome.Status.INVALID_TARGET, "HTTP 404 UNREGISTERED");
          }
          return PushOutcome.delivered();
        });
    var eventId = publish("NORMAL", "INFO");

    dispatcher.dispatchPending();

    var body = deliveries(eventId).extract();
    var items = body.jsonPath().<Map<String, Object>>getList("items");
    assertRecord(items, permanent.id(), 1, "PERMANENT_FAILURE", "HTTP 400 SENDER_ID");
    assertRecord(items, invalid.id(), 1, "INVALID_TARGET", "HTTP 404 UNREGISTERED");
    assertRecord(
        items, unsupported.id(), 1, "UNSUPPORTED_PROVIDER", "no otherprovider provider configured");
    assertFalse(body.asString().contains(permanentToken));
    assertFalse(body.asString().contains(invalidToken));
  }

  @Test
  void eachRetryIsAnotherAttempt() throws SQLException {
    var client = TestClients.register("retried");
    setTarget(client, FakePushProvider.NAME, "deliveries-" + UUID.randomUUID());
    fake.answer((to, message) -> TEMPORARY);
    var eventId = publish("NORMAL", "INFO");
    dispatcher.dispatchPending();
    makeRetriesDue(eventId);
    dispatcher.dispatchPending();

    fake.answer((to, message) -> PushOutcome.delivered());
    makeRetriesDue(eventId);
    dispatcher.dispatchPending();

    var records = recordsOf(items(eventId), client.id());
    assertEquals(3, records.size());
    assertEquals(List.of(1, 2, 3), records.stream().map(r -> r.get("attempt")).toList());
    assertEquals(
        List.of("TRANSIENT_FAILURE", "TRANSIENT_FAILURE", "DELIVERED"),
        records.stream().map(r -> r.get("outcome")).toList());
    assertEquals("HTTP 503 UNAVAILABLE", records.get(0).get("detail"));
    // Oldest first.
    assertTrue(
        Instant.parse((String) records.get(1).get("at"))
            .isAfter(Instant.parse((String) records.get(0).get("at"))));
  }

  @Test
  void aRetryToADeviceThatMutedTheEventOrLostItsTargetMeanwhileSaysSo() throws SQLException {
    var muted = TestClients.register("muted-meanwhile");
    setTarget(muted, FakePushProvider.NAME, "deliveries-" + UUID.randomUUID());
    var lost = TestClients.register("lost-target");
    setTarget(lost, FakePushProvider.NAME, "deliveries-" + UUID.randomUUID());
    fake.answer((to, message) -> TEMPORARY);
    var eventId = publish("NORMAL", "INFO");
    dispatcher.dispatchPending();

    setPreferences(muted, false, "LOW", List.of(), List.of());
    asClient(lost.clientKey()).delete(CLIENT + "/push-target").then().statusCode(200);
    makeRetriesDue(eventId);
    dispatcher.dispatchPending();

    var items = items(eventId);
    var mutedRecords = recordsOf(items, muted.id());
    assertEquals(2, mutedRecords.size());
    assertEquals(2, mutedRecords.get(1).get("attempt"));
    assertEquals("FILTERED", mutedRecords.get(1).get("outcome"));
    assertEquals("pushes paused", mutedRecords.get(1).get("detail"));
    var lostRecords = recordsOf(items, lost.id());
    assertEquals(2, lostRecords.size());
    assertEquals("NO_TARGET", lostRecords.get(1).get("outcome"));
    assertEquals(0, retriesOf(eventId, muted.id()), "neither is retried again");
    assertEquals(0, retriesOf(eventId, lost.id()), "neither is retried again");
  }

  @Test
  void anEventNotDispatchedYetHasNoRecords() {
    var eventId = publish("NORMAL", "INFO");

    deliveries(eventId).body("items", empty());
  }

  @Test
  void anUnknownOrDeletedEventIsNotFound() {
    var eventId = publish("NORMAL", "INFO");
    dispatcher.dispatchPending();
    asAdmin().delete(ADMIN_EVENTS + "/" + eventId).then().statusCode(204);

    asAdmin()
        .get(ADMIN_EVENTS + "/" + eventId + "/deliveries")
        .then()
        .statusCode(404)
        .body("title", equalTo("Event not found"));
    asAdmin().get(ADMIN_EVENTS + "/" + UUID.randomUUID() + "/deliveries").then().statusCode(404);
    asAdmin().get(ADMIN_EVENTS + "/not-a-uuid/deliveries").then().statusCode(404);
  }

  @Test
  void theRecordsRequireTheAdminToken() {
    var client = TestClients.register("deliveries-unauthorized");
    var eventId = publish("NORMAL", "INFO");
    var path = ADMIN_EVENTS + "/" + eventId + "/deliveries";

    given().get(path).then().statusCode(401);
    given()
        .header("Authorization", "Bearer wrong-admin-token-0123456789abcdef")
        .get(path)
        .then()
        .statusCode(401);
    asProducer(producer.apiKey()).get(path).then().statusCode(401);
    asClient(client.clientKey()).get(path).then().statusCode(401);
  }

  @Test
  void failingToRecordADeliveryNeitherFailsNorRepeatsAPush() throws SQLException {
    var client = TestClients.register("not-recorded");
    var token = "deliveries-" + UUID.randomUUID();
    setTarget(client, FakePushProvider.NAME, token);
    var eventId = publish("NORMAL", "INFO");
    execute(
        """
        CREATE FUNCTION fail_deliveries() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN
            RAISE EXCEPTION 'deliveries cannot be recorded';
        END $$
        """);
    try {
      execute(
          "CREATE TRIGGER fail_deliveries BEFORE INSERT ON event_deliveries FOR EACH ROW"
              + " WHEN (NEW.client_id = '"
              + client.id()
              + "') EXECUTE FUNCTION fail_deliveries()");

      assertEquals(1, dispatcher.dispatchPending());
      dispatcher.dispatchPending();

      assertEquals(1, sentTo(eventId).stream().filter(token::equals).count());
      assertTrue(recordsOf(items(eventId), client.id()).isEmpty());
      // The device's last result is recorded all the same.
      asAdmin()
          .get(ADMIN + "/" + client.id())
          .then()
          .body("pushStatus.lastSuccess.eventId", equalTo(eventId.toString()));
    } finally {
      execute("DROP TRIGGER IF EXISTS fail_deliveries ON event_deliveries");
      execute("DROP FUNCTION fail_deliveries()");
    }
  }

  private static io.restassured.response.ValidatableResponse deliveries(UUID eventId) {
    return asAdmin()
        .get(ADMIN_EVENTS + "/" + eventId + "/deliveries")
        .then()
        .statusCode(200)
        .contentType(ContentType.JSON);
  }

  private static List<Map<String, Object>> items(UUID eventId) {
    return deliveries(eventId).extract().jsonPath().getList("items");
  }

  private static List<Map<String, Object>> recordsOf(List<Map<String, Object>> items, UUID id) {
    return items.stream().filter(item -> id.toString().equals(item.get("clientId"))).toList();
  }

  private static void assertRecord(
      List<Map<String, Object>> items, UUID clientId, int attempt, String outcome, String detail) {
    var records = recordsOf(items, clientId);
    assertEquals(1, records.size(), outcome);
    assertEquals(attempt, records.get(0).get("attempt"));
    assertEquals(outcome, records.get(0).get("outcome"));
    assertEquals(detail, records.get(0).get("detail"));
  }

  private static TestClients.Registered withPreferences(
      String name,
      boolean enabled,
      String minimumSeverity,
      List<String> mutedCategories,
      List<UUID> mutedProducerIds) {
    var client = TestClients.register(name);
    var token = "deliveries-" + UUID.randomUUID();
    TOKENS.put(client, token);
    setTarget(client, FakePushProvider.NAME, token);
    setPreferences(client, enabled, minimumSeverity, mutedCategories, mutedProducerIds);
    return client;
  }

  private static void setPreferences(
      TestClients.Registered client,
      boolean enabled,
      String minimumSeverity,
      List<String> mutedCategories,
      List<UUID> mutedProducerIds) {
    asClient(client.clientKey())
        .contentType(ContentType.JSON)
        .body(
            Map.of(
                "enabled", enabled,
                "minimumSeverity", minimumSeverity,
                "mutedCategories", mutedCategories,
                "mutedProducerIds", mutedProducerIds.stream().map(UUID::toString).toList()))
        .put(CLIENT + "/push-preferences")
        .then()
        .statusCode(200);
  }

  private static void setTarget(TestClients.Registered client, String provider, String token) {
    asClient(client.clientKey())
        .contentType(ContentType.JSON)
        .body(Map.of("provider", provider, "token", token))
        .put(CLIENT + "/push-target")
        .then()
        .statusCode(200);
  }

  private UUID publish(String severity, String category) {
    return UUID.fromString(
        asProducer(producer.apiKey())
            .contentType(ContentType.JSON)
            .body(Map.of("category", category, "severity", severity, "title", "Delivery"))
            .post("/api/v1/events")
            .then()
            .statusCode(201)
            .extract()
            .path("id"));
  }

  private List<String> sentTo(UUID eventId) {
    return fake.sent().stream()
        .filter(sent -> eventId.toString().equals(sent.message().data().get("eventId")))
        .map(FakePushProvider.Sent::token)
        .toList();
  }

  private void makeRetriesDue(UUID eventId) throws SQLException {
    execute(
        "UPDATE push_retries SET next_attempt_at = now() - interval '1 second'"
            + " WHERE event_id = '"
            + eventId
            + "'");
  }

  private long retriesOf(UUID eventId, UUID clientId) throws SQLException {
    try (var connection = dataSource.getConnection();
        var statement =
            connection.prepareStatement(
                "SELECT count(*) FROM push_retries WHERE event_id = ? AND client_id = ?")) {
      statement.setObject(1, eventId);
      statement.setObject(2, clientId);
      try (var rows = statement.executeQuery()) {
        rows.next();
        return rows.getLong(1);
      }
    }
  }

  private void execute(String sql) throws SQLException {
    try (var connection = dataSource.getConnection();
        var statement = connection.createStatement()) {
      statement.execute(sql);
    }
  }
}
