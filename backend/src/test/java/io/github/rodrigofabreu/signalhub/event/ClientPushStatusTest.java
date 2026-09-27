package io.github.rodrigofabreu.signalhub.event;

import static io.github.rodrigofabreu.signalhub.TestClients.ADMIN;
import static io.github.rodrigofabreu.signalhub.TestClients.CLIENT;
import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.github.rodrigofabreu.signalhub.TestProducers.asProducer;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.hasKey;
import static org.hamcrest.Matchers.not;
import static org.hamcrest.Matchers.notNullValue;
import static org.hamcrest.Matchers.nullValue;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.agroal.api.AgroalDataSource;
import io.github.rodrigofabreu.signalhub.TestClients;
import io.github.rodrigofabreu.signalhub.TestProducers;
import io.github.rodrigofabreu.signalhub.push.FakePushProvider;
import io.github.rodrigofabreu.signalhub.push.PushOutcome;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import io.restassured.path.json.JsonPath;
import jakarta.inject.Inject;
import java.sql.SQLException;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * Each client's latest push results in the management API, recorded by the dispatcher on real
 * PostgreSQL with the fake provider. The scheduler is off in tests, so each test runs the
 * dispatcher itself.
 */
@QuarkusTest
class ClientPushStatusTest {

  private static final PushOutcome TEMPORARY =
      new PushOutcome(PushOutcome.Status.TRANSIENT_FAILURE, "down");
  private static final PushOutcome PERMANENT =
      new PushOutcome(PushOutcome.Status.PERMANENT_FAILURE, "rejected");

  @Inject EventPushDispatcher dispatcher;
  @Inject FakePushProvider fake;
  @Inject AgroalDataSource dataSource;

  private String apiKey;

  @BeforeEach
  void setUp() {
    // Events from other tests wait in the outbox too; send them before each test's own.
    dispatcher.dispatchPending();
    fake.answer((token, message) -> PushOutcome.delivered());
    apiKey = TestProducers.register("push-status").apiKey();
  }

  @Test
  void aNewClientHasNoResults() {
    var client = TestClients.register("push-status");

    asAdmin()
        .get(ADMIN + "/" + client.id())
        .then()
        .statusCode(200)
        .body("pushStatus.lastSuccess", nullValue())
        .body("pushStatus.lastFailure", nullValue())
        .body("pushStatus.pendingRetries", equalTo(0));
  }

  @Test
  void aDeliveredPushIsTheLastSuccess() {
    var client = TestClients.register("push-status");
    setTarget(client.clientKey(), "status-" + UUID.randomUUID());
    var before = Instant.now();
    var eventId = publish("Delivered");

    dispatcher.dispatchPending();

    var status = pushStatus(client.id());
    assertEquals(eventId.toString(), status.getString("lastSuccess.eventId"));
    assertFalse(Instant.parse(status.getString("lastSuccess.at")).isBefore(before.minusSeconds(1)));
    assertNull(status.get("lastFailure"));
    assertEquals(0, status.getInt("pendingRetries"));
    // The listing shows the same results.
    asAdmin()
        .get(ADMIN)
        .then()
        .statusCode(200)
        .body(
            "items.find { it.id == '" + client.id() + "' }.pushStatus.lastSuccess.eventId",
            equalTo(eventId.toString()));
  }

  @Test
  void eachSendOverwritesTheLastSuccess() {
    var client = TestClients.register("push-status");
    setTarget(client.clientKey(), "status-" + UUID.randomUUID());
    publish("First");
    dispatcher.dispatchPending();
    var second = publish("Second");

    dispatcher.dispatchPending();

    assertEquals(second.toString(), pushStatus(client.id()).getString("lastSuccess.eventId"));
  }

  @Test
  void aPermanentFailureIsTheLastFailureWithoutTheToken() {
    var client = TestClients.register("push-status");
    var token = "status-" + UUID.randomUUID();
    setTarget(client.clientKey(), token);
    var delivered = publish("Delivered first");
    dispatcher.dispatchPending();
    fake.answer((to, message) -> to.equals(token) ? PERMANENT : PushOutcome.delivered());
    var rejected = publish("Rejected");

    dispatcher.dispatchPending();

    var body = asAdmin().get(ADMIN + "/" + client.id()).then().statusCode(200).extract();
    var status = body.jsonPath().setRootPath("pushStatus");
    assertEquals(rejected.toString(), status.getString("lastFailure.eventId"));
    assertEquals("PERMANENT_FAILURE", status.getString("lastFailure.result"));
    assertNotNull(status.getString("lastFailure.at"));
    // A failure leaves the last success as it was.
    assertEquals(delivered.toString(), status.getString("lastSuccess.eventId"));
    assertEquals(0, status.getInt("pendingRetries"));
    assertFalse(body.asString().contains(token), "the push token is never returned");
  }

  @Test
  void aRejectedTargetIsAnInvalidTargetFailure() {
    var client = TestClients.register("push-status");
    var token = "status-" + UUID.randomUUID();
    setTarget(client.clientKey(), token);
    fake.answer(
        (to, message) ->
            to.equals(token)
                ? new PushOutcome(PushOutcome.Status.INVALID_TARGET, "unregistered")
                : PushOutcome.delivered());
    var eventId = publish("Unregistered");

    dispatcher.dispatchPending();

    asAdmin()
        .get(ADMIN + "/" + client.id())
        .then()
        .statusCode(200)
        .body("pushTarget", nullValue())
        .body("pushStatus.lastFailure.eventId", equalTo(eventId.toString()))
        .body("pushStatus.lastFailure.result", equalTo("INVALID_TARGET"));
  }

  @Test
  void aTemporaryFailureIsCountedUntilTheRetrySucceeds() throws SQLException {
    var client = TestClients.register("push-status");
    setTarget(client.clientKey(), "status-" + UUID.randomUUID());
    fake.answer((to, message) -> TEMPORARY);
    var eventId = publish("Provider down for a moment");

    dispatcher.dispatchPending();

    var failed = pushStatus(client.id());
    assertEquals(eventId.toString(), failed.getString("lastFailure.eventId"));
    assertEquals("TRANSIENT_FAILURE", failed.getString("lastFailure.result"));
    assertNull(failed.get("lastSuccess"));
    assertEquals(1, failed.getInt("pendingRetries"));

    fake.answer((to, message) -> PushOutcome.delivered());
    makeRetriesDue(eventId);
    dispatcher.dispatchPending();

    var retried = pushStatus(client.id());
    assertEquals(eventId.toString(), retried.getString("lastSuccess.eventId"));
    assertTrue(
        Instant.parse(retried.getString("lastSuccess.at"))
            .isAfter(Instant.parse(retried.getString("lastFailure.at"))));
    assertEquals("TRANSIENT_FAILURE", retried.getString("lastFailure.result"));
    assertEquals(0, retried.getInt("pendingRetries"));
  }

  @Test
  void pendingRetriesCountEveryPushWaitingForTheClient() throws SQLException {
    var client = TestClients.register("push-status");
    setTarget(client.clientKey(), "status-" + UUID.randomUUID());
    fake.answer((to, message) -> TEMPORARY);
    var first = publish("Waiting");
    publish("Waiting too");
    dispatcher.dispatchPending();
    // A failed retry keeps waiting.
    makeRetriesDue(first);
    dispatcher.dispatchPending();

    assertEquals(2, pushStatus(client.id()).getInt("pendingRetries"));
    asAdmin()
        .get(ADMIN)
        .then()
        .statusCode(200)
        .body(
            "items.find { it.id == '" + client.id() + "' }.pushStatus.pendingRetries", equalTo(2));
  }

  @Test
  void aRevokedClientKeepsItsResults() {
    var client = TestClients.register("push-status");
    var token = "status-" + UUID.randomUUID();
    setTarget(client.clientKey(), token);
    var delivered = publish("Delivered before revocation");
    dispatcher.dispatchPending();
    fake.answer((to, message) -> to.equals(token) ? PERMANENT : PushOutcome.delivered());
    var rejected = publish("Rejected before revocation");
    dispatcher.dispatchPending();

    asAdmin().post(ADMIN + "/" + client.id() + "/revoke").then().statusCode(200);
    publish("After revocation");
    dispatcher.dispatchPending();

    asAdmin()
        .get(ADMIN + "/" + client.id())
        .then()
        .statusCode(200)
        .body("revokedAt", notNullValue())
        .body("pushStatus.lastSuccess.eventId", equalTo(delivered.toString()))
        .body("pushStatus.lastFailure.eventId", equalTo(rejected.toString()))
        .body("pushStatus.lastFailure.result", equalTo("PERMANENT_FAILURE"));
  }

  @Test
  void theClientApiDoesNotShowPushResults() {
    var client = TestClients.register("push-status");
    setTarget(client.clientKey(), "status-" + UUID.randomUUID());
    publish("Not for the client");
    dispatcher.dispatchPending();

    asClient(client.clientKey())
        .get(CLIENT)
        .then()
        .statusCode(200)
        .body("$", not(hasKey("pushStatus")));
  }

  @Test
  void failingToRecordAResultNeitherFailsNorRepeatsAPush() throws SQLException {
    var delivered = TestClients.register("push-status");
    var deliveredToken = "status-" + UUID.randomUUID();
    setTarget(delivered.clientKey(), deliveredToken);
    var retried = TestClients.register("push-status");
    var retriedToken = "status-" + UUID.randomUUID();
    setTarget(retried.clientKey(), retriedToken);
    fake.answer((to, message) -> to.equals(retriedToken) ? TEMPORARY : PushOutcome.delivered());
    var eventId = publish("Not recorded");

    try {
      failRecordingFor(delivered.id(), retried.id());
      assertEquals(1, dispatcher.dispatchPending());

      // Both were sent once, the event's dispatch completed, and the temporary failure still
      // waits for its retry.
      assertEquals(1, sentTo(eventId, deliveredToken));
      assertEquals(1, sentTo(eventId, retriedToken));
      assertFalse(pending(eventId));
      assertEquals(1, pushStatus(retried.id()).getInt("pendingRetries"));
      assertNull(pushStatus(delivered.id()).get("lastSuccess"));
      assertNull(pushStatus(retried.id()).get("lastFailure"));

      // The retry is sent and completed as well.
      fake.answer((to, message) -> PushOutcome.delivered());
      makeRetriesDue(eventId);
      dispatcher.dispatchPending();
      dispatcher.dispatchPending();
      assertEquals(0, sentTo(eventId, deliveredToken));
      assertEquals(1, sentTo(eventId, retriedToken));
      assertEquals(0, pushStatus(retried.id()).getInt("pendingRetries"));
      assertNull(pushStatus(retried.id()).get("lastSuccess"));
    } finally {
      execute("DROP TRIGGER fail_push_results ON clients");
      execute("DROP FUNCTION fail_push_results()");
    }
  }

  private static JsonPath pushStatus(UUID clientId) {
    return asAdmin()
        .get(ADMIN + "/" + clientId)
        .then()
        .statusCode(200)
        .extract()
        .jsonPath()
        .setRootPath("pushStatus");
  }

  private static void setTarget(String clientKey, String token) {
    asClient(clientKey)
        .contentType(ContentType.JSON)
        .body(Map.of("provider", FakePushProvider.NAME, "token", token))
        .put(CLIENT + "/push-target")
        .then()
        .statusCode(200);
  }

  private UUID publish(String title) {
    return UUID.fromString(
        asProducer(apiKey)
            .contentType(ContentType.JSON)
            .body(Map.of("category", "INFO", "severity", "NORMAL", "title", title))
            .post("/api/v1/events")
            .then()
            .statusCode(201)
            .extract()
            .path("id"));
  }

  private long sentTo(UUID eventId, String token) {
    return fake.sent().stream()
        .filter(sent -> eventId.toString().equals(sent.message().data().get("eventId")))
        .filter(sent -> sent.token().equals(token))
        .count();
  }

  private boolean pending(UUID eventId) throws SQLException {
    try (var connection = dataSource.getConnection();
        var statement =
            connection.prepareStatement("SELECT 1 FROM push_dispatches WHERE event_id = ?")) {
      statement.setObject(1, eventId);
      try (var rows = statement.executeQuery()) {
        return rows.next();
      }
    }
  }

  private void makeRetriesDue(UUID eventId) throws SQLException {
    try (var connection = dataSource.getConnection();
        var statement =
            connection.prepareStatement(
                "UPDATE push_retries SET next_attempt_at = now() - interval '1 second'"
                    + " WHERE event_id = ?")) {
      statement.setObject(1, eventId);
      statement.executeUpdate();
    }
  }

  /** Makes every write of these clients' push results fail, as a database error would. */
  private void failRecordingFor(UUID... clientIds) throws SQLException {
    var ids = new StringBuilder();
    for (var id : clientIds) {
      ids.append(ids.isEmpty() ? "" : ", ").append('\'').append(id).append('\'');
    }
    execute(
        """
        CREATE FUNCTION fail_push_results() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN
            RAISE EXCEPTION 'push results cannot be recorded';
        END $$
        """);
    execute(
        "CREATE TRIGGER fail_push_results BEFORE UPDATE OF last_push_succeeded_at,"
            + " last_push_failed_at ON clients FOR EACH ROW WHEN (NEW.id IN ("
            + ids
            + ")) EXECUTE FUNCTION fail_push_results()");
  }

  private void execute(String sql) throws SQLException {
    try (var connection = dataSource.getConnection();
        var statement = connection.createStatement()) {
      statement.execute(sql);
    }
  }
}
