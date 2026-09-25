package io.github.rodrigofabreu.signalhub.event;

import static io.github.rodrigofabreu.signalhub.TestClients.ADMIN;
import static io.github.rodrigofabreu.signalhub.TestClients.CLIENT;
import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.github.rodrigofabreu.signalhub.TestProducers.asProducer;
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
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * Event-triggered push dispatch through the outbox, on real PostgreSQL with the fake provider. The
 * scheduler is off in tests, so each test runs the dispatcher itself.
 */
@QuarkusTest
class EventPushDispatchTest {

  @Inject EventPushDispatcher dispatcher;
  @Inject FakePushProvider fake;
  @Inject AgroalDataSource dataSource;

  private String apiKey;

  @BeforeEach
  void setUp() {
    // Events from other tests wait in the outbox too; send them before each test's own.
    dispatcher.dispatchPending();
    fake.answer((token, message) -> PushOutcome.delivered());
    apiKey = TestProducers.register("push-dispatch").apiKey();
  }

  @Test
  void aPublishedEventIsPushedToEveryClientWithATarget() throws SQLException {
    var first = clientWithTarget();
    var second = clientWithTarget();
    TestClients.register("no-target");
    var eventId = publish("Deploy needs approval", "Production deploy #42 is waiting.");

    // Stored with the event, before anything is sent.
    assertTrue(pending(eventId));
    assertTrue(fake.sent().isEmpty());

    assertEquals(1, dispatcher.dispatchPending());

    // Clients registered by other tests get it too; each of this test's gets it once.
    assertEquals(1, sentFor(eventId, first).size());
    assertEquals(1, sentFor(eventId, second).size());
    var message = sentFor(eventId, first).get(0).message();
    assertEquals("Deploy needs approval", message.title());
    assertEquals("Production deploy #42 is waiting.", message.body());
    assertEquals(
        Map.of("eventId", eventId.toString(), "category", "ACTION_REQUIRED", "severity", "HIGH"),
        message.data());
    assertFalse(pending(eventId));
  }

  @Test
  void anEventIsDispatchedOnce() {
    clientWithTarget();
    var eventId = publish("Once", null);
    dispatcher.dispatchPending();
    fake.answer((token, message) -> PushOutcome.delivered());

    assertEquals(0, dispatcher.dispatchPending());
    assertTrue(sentFor(eventId).isEmpty());
  }

  @Test
  void anEventWithoutAMessageHasNoBody() {
    clientWithTarget();
    var eventId = publish("Title only", null);

    dispatcher.dispatchPending();

    assertNull(sentFor(eventId).get(0).message().body());
  }

  @Test
  void aRevokedClientGetsNoPush() {
    var client = TestClients.register("revoked");
    setTarget(client.clientKey(), "revoked-" + UUID.randomUUID());
    asAdmin().post(ADMIN + "/" + client.id() + "/revoke").then().statusCode(200);
    var eventId = publish("After revocation", null);

    dispatcher.dispatchPending();

    assertTrue(sentFor(eventId).isEmpty());
  }

  @Test
  void aFailedSendDoesNotHoldBackTheEvent() throws SQLException {
    var token = clientWithTarget();
    fake.answer((to, message) -> new PushOutcome(PushOutcome.Status.TRANSIENT_FAILURE, "down"));
    var eventId = publish("Provider down", null);

    assertEquals(1, dispatcher.dispatchPending());

    // One attempt per client for now; retries are roadmap R13.
    assertEquals(1, sentFor(eventId, token).size());
    assertFalse(pending(eventId));
  }

  @Test
  void aClaimLeftByAStoppedDispatcherExpiresAndTheEventIsSentAgain() throws SQLException {
    var token = clientWithTarget();
    var eventId = publish("Interrupted", null);
    claim(eventId, "now() + interval '1 minute'");

    assertEquals(0, dispatcher.dispatchPending());
    assertTrue(sentFor(eventId).isEmpty());

    claim(eventId, "now() - interval '1 second'");

    assertEquals(1, dispatcher.dispatchPending());
    assertEquals(1, sentFor(eventId, token).size());
  }

  @Test
  void deletingAnEventDropsItsPendingPush() throws SQLException {
    var eventId = publish("Deleted", null);
    try (var connection = dataSource.getConnection();
        var statement = connection.prepareStatement("DELETE FROM events WHERE id = ?")) {
      statement.setObject(1, eventId);
      statement.executeUpdate();
    }

    assertFalse(pending(eventId));
  }

  private String clientWithTarget() {
    var client = TestClients.register("push-dispatch");
    var token = "dispatch-" + UUID.randomUUID();
    setTarget(client.clientKey(), token);
    return token;
  }

  private static void setTarget(String clientKey, String token) {
    asClient(clientKey)
        .contentType(ContentType.JSON)
        .body(Map.of("provider", FakePushProvider.NAME, "token", token))
        .put(CLIENT + "/push-target")
        .then()
        .statusCode(200);
  }

  private UUID publish(String title, String message) {
    var body = new HashMap<String, Object>();
    body.put("category", "ACTION_REQUIRED");
    body.put("severity", "HIGH");
    body.put("title", title);
    if (message != null) {
      body.put("message", message);
    }
    return UUID.fromString(
        asProducer(apiKey)
            .contentType(ContentType.JSON)
            .body(body)
            .post("/api/v1/events")
            .then()
            .statusCode(201)
            .extract()
            .path("id"));
  }

  private List<FakePushProvider.Sent> sentFor(UUID eventId) {
    return fake.sent().stream()
        .filter(sent -> eventId.toString().equals(sent.message().data().get("eventId")))
        .toList();
  }

  private List<FakePushProvider.Sent> sentFor(UUID eventId, String token) {
    return sentFor(eventId).stream().filter(sent -> sent.token().equals(token)).toList();
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

  private void claim(UUID eventId, String until) throws SQLException {
    try (var connection = dataSource.getConnection();
        var statement =
            connection.prepareStatement(
                "UPDATE push_dispatches SET claimed_until = " + until + " WHERE event_id = ?")) {
      statement.setObject(1, eventId);
      assertEquals(1, statement.executeUpdate());
    }
  }
}
