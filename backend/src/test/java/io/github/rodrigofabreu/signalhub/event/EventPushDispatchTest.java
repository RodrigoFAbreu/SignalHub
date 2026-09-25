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
import io.github.rodrigofabreu.signalhub.push.PushMessage;
import io.github.rodrigofabreu.signalhub.push.PushOutcome;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import jakarta.inject.Inject;
import java.sql.SQLException;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * Stored events are queued in PostgreSQL and pushed to every client with a push target. Background
 * dispatch is off in tests, so each test dispatches explicitly and nothing is sent in between.
 */
@QuarkusTest
class EventPushDispatchTest {

  private static TestProducers.Registered producer;

  @Inject EventPushDispatcher dispatcher;
  @Inject FakePushProvider fake;
  @Inject AgroalDataSource dataSource;

  @BeforeEach
  void deliverByDefault() {
    if (producer == null) {
      producer = TestProducers.register("push-dispatch");
    }
    // Earlier tests leave queued events; dispatch them before this test starts watching.
    dispatcher.dispatchPending();
    fake.answer((token, message) -> PushOutcome.delivered());
  }

  @Test
  void aStoredEventWaitsInTheQueueUntilDispatched() throws SQLException {
    var client = withTarget("queued");

    var eventId = publish("{\"category\": \"INFO\", \"severity\": \"LOW\", \"title\": \"Queued\"}");

    // Committed with the event, so a restart before dispatch does not lose the push.
    assertTrue(isQueued(eventId));
    assertTrue(sentTo(client, eventId).isEmpty());

    assertTrue(dispatcher.dispatchPending() >= 1);

    assertFalse(isQueued(eventId));
    assertEquals(1, sentTo(client, eventId).size());
  }

  @Test
  void everyClientWithATargetGetsTheEvent() {
    var first = withTarget("first");
    var second = withTarget("second");
    var revoked = withTarget("revoked");
    asAdmin().post(ADMIN + "/" + revoked.id() + "/revoke").then().statusCode(200);

    var eventId =
        publish(
            """
            {"category": "ACTION_REQUIRED", "severity": "HIGH",
             "title": "Review required", "message": "A human gate is waiting.",
             "metadata": {"run": 42}}
            """);
    dispatcher.dispatchPending();

    for (var client : List.of(first, second)) {
      var sent = sentTo(client, eventId);
      assertEquals(1, sent.size());
      assertEquals("Review required", sent.get(0).title());
      assertEquals("A human gate is waiting.", sent.get(0).body());
      // Only the event ID: the client fetches the event, the push is a signal to look.
      assertEquals(Map.of("eventId", eventId.toString()), sent.get(0).data());
    }
    assertTrue(sentTo(revoked, eventId).isEmpty());
  }

  @Test
  void aDispatchedEventIsNotPushedAgain() {
    var client = withTarget("once");
    var eventId = publish("{\"category\": \"INFO\", \"severity\": \"LOW\", \"title\": \"Once\"}");

    dispatcher.dispatchPending();
    assertEquals(0, dispatcher.dispatchPending());

    assertEquals(1, sentTo(client, eventId).size());
  }

  @Test
  void aFailedSendDoesNotKeepOtherClientsFromTheEvent() {
    var failing = withTarget("failing");
    var working = withTarget("working");
    fake.answer(
        (token, message) ->
            token.equals(failing.token())
                ? new PushOutcome(PushOutcome.Status.TRANSIENT_FAILURE, "unavailable")
                : PushOutcome.delivered());

    var eventId = publish("{\"category\": \"INFO\", \"severity\": \"LOW\", \"title\": \"Both\"}");
    dispatcher.dispatchPending();

    assertEquals(1, sentTo(failing, eventId).size());
    assertEquals(1, sentTo(working, eventId).size());
  }

  @Test
  void anEventWithoutMessageHasNoBody() {
    var client = withTarget("no-body");

    var withoutMessage =
        publish("{\"category\": \"INFO\", \"severity\": \"LOW\", \"title\": \"No body\"}");
    var emptyMessage =
        publish(
            "{\"category\": \"INFO\", \"severity\": \"LOW\", \"title\": \"Empty\", \"message\": \"\"}");
    dispatcher.dispatchPending();

    assertNull(sentTo(client, withoutMessage).get(0).body());
    assertNull(sentTo(client, emptyMessage).get(0).body());
  }

  @Test
  void aLongMessageIsShortenedForThePush() {
    var eventId = UUID.randomUUID();
    var message = EventPushDispatcher.toMessage(new PendingPush(eventId, "Long", "x".repeat(4000)));

    assertEquals(EventPushDispatcher.MAX_BODY_LENGTH, message.body().length());
    assertTrue(message.body().endsWith("…"));
  }

  @Test
  void shorteningNeverSplitsACharacter() {
    // U+1F600 takes two UTF-16 units; a length limit in units could cut one in half.
    var emoji = "😀";
    var text = emoji.repeat(EventPushDispatcher.MAX_BODY_LENGTH + 1);

    var body = EventPushDispatcher.toMessage(new PendingPush(UUID.randomUUID(), "t", text)).body();

    assertEquals(EventPushDispatcher.MAX_BODY_LENGTH, body.codePointCount(0, body.length()));
    assertEquals(emoji.repeat(EventPushDispatcher.MAX_BODY_LENGTH - 1) + "…", body);
  }

  @Test
  void aMessageAtTheLimitIsKept() {
    var text = "y".repeat(EventPushDispatcher.MAX_BODY_LENGTH);

    var body = EventPushDispatcher.toMessage(new PendingPush(UUID.randomUUID(), "t", text)).body();

    assertEquals(text, body);
  }

  private record Target(UUID id, String token) {}

  private Target withTarget(String name) {
    var client = TestClients.register(name);
    var token = name + "-" + UUID.randomUUID();
    asClient(client.clientKey())
        .contentType(ContentType.JSON)
        .body("{\"provider\": \"" + FakePushProvider.NAME + "\", \"token\": \"" + token + "\"}")
        .when()
        .put(CLIENT + "/push-target")
        .then()
        .statusCode(200);
    return new Target(client.id(), token);
  }

  private static UUID publish(String event) {
    return UUID.fromString(
        asProducer(producer.apiKey())
            .contentType(ContentType.JSON)
            .body(event)
            .when()
            .post("/api/v1/events")
            .then()
            .statusCode(201)
            .extract()
            .path("id"));
  }

  private List<PushMessage> sentTo(Target client, UUID eventId) {
    return fake.sent().stream()
        .filter(sent -> sent.token().equals(client.token()))
        .map(FakePushProvider.Sent::message)
        .filter(message -> eventId.toString().equals(message.data().get("eventId")))
        .toList();
  }

  private boolean isQueued(UUID eventId) throws SQLException {
    try (var connection = dataSource.getConnection();
        var statement =
            connection.prepareStatement("SELECT 1 FROM pending_pushes WHERE event_id = ?")) {
      statement.setObject(1, eventId);
      try (var row = statement.executeQuery()) {
        return row.next();
      }
    }
  }
}
