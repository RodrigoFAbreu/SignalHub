package io.github.rodrigofabreu.signalhub.event;

import static io.github.rodrigofabreu.signalhub.TestClients.CLIENT;
import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asProducer;
import static io.github.rodrigofabreu.signalhub.event.Asking.EVENTS;
import static io.github.rodrigofabreu.signalhub.event.Asking.MERGE_OR_HOLD;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

import io.github.rodrigofabreu.signalhub.TestClients;
import io.github.rodrigofabreu.signalhub.TestProducers;
import io.github.rodrigofabreu.signalhub.push.FakePushProvider;
import io.github.rodrigofabreu.signalhub.push.PushMessage;
import io.github.rodrigofabreu.signalhub.push.PushOutcome;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import jakarta.inject.Inject;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/** The "Tap to answer" line: first in the push's text, and only for the people who may answer. */
@QuarkusTest
class QuestionPushLineTest {

  @Inject EventPushDispatcher dispatcher;
  @Inject FakePushProvider fake;

  private TestProducers.Registered producer;
  private TestClients.Registered owner;
  private String ownerToken;
  private TestClients.Registered answerer;
  private String answererToken;
  private TestClients.Registered reader;
  private String readerToken;

  @BeforeEach
  void setUp() {
    dispatcher.dispatchPending();
    fake.answer((token, message) -> PushOutcome.delivered());
    producer = TestProducers.registerPublic("push-line");
    owner = TestClients.register("push-line-owner");
    ownerToken = target(owner);
    answerer = TestClients.registerSubscribed("BASIC", "push-line-answerer", producer);
    answererToken = target(answerer);
    reader = TestClients.registerSubscribed("BASIC", "push-line-reader", producer);
    readerToken = target(reader);
    asClient(owner.clientKey())
        .put(CLIENT + "/producers/" + producer.id() + "/answerers/" + answerer.userId())
        .then()
        .statusCode(200);
  }

  private static String target(TestClients.Registered client) {
    var token = "line-" + UUID.randomUUID();
    asClient(client.clientKey())
        .contentType(ContentType.JSON)
        .body(Map.of("provider", FakePushProvider.NAME, "token", token))
        .put(CLIENT + "/push-target")
        .then()
        .statusCode(200);
    return token;
  }

  private UUID publish(String ask, String message) {
    var message_ = message == null ? "" : ", \"message\": \"" + message + "\"";
    return UUID.fromString(
        asProducer(producer.apiKey())
            .contentType(ContentType.JSON)
            .body(
                """
                {"category": "ACTION_REQUIRED", "severity": "HIGH", "title": "Merge it?"%s,
                 "ask": %s}
                """
                    .formatted(message_, ask))
            .post(EVENTS)
            .then()
            .statusCode(201)
            .extract()
            .path("id"));
  }

  private PushMessage pushTo(UUID event, String token) {
    return fake.sent().stream()
        .filter(s -> s.token().equals(token))
        .filter(s -> event.toString().equals(s.message().data().get("eventId")))
        .filter(s -> !s.message().isDataOnly())
        .map(FakePushProvider.Sent::message)
        .findFirst()
        .orElseThrow();
  }

  @Test
  void theOwnerAndAnAnswererGetTheLineFirstAndTheMessageAfterIt() {
    var event = publish(MERGE_OR_HOLD, "CI passed.");
    dispatcher.dispatchPending();

    assertEquals("Tap to answer · Merge or Hold\nCI passed.", pushTo(event, ownerToken).body());
    assertEquals("Tap to answer · Merge or Hold\nCI passed.", pushTo(event, answererToken).body());
    assertEquals("Merge it?", pushTo(event, ownerToken).title());
  }

  @Test
  void aPersonWhoMayNotAnswerGetsTheEventsUsualText() {
    var event = publish(MERGE_OR_HOLD, "CI passed.");
    dispatcher.dispatchPending();

    assertEquals("CI passed.", pushTo(event, readerToken).body());
    assertEquals(
        Map.of("eventId", event.toString(), "category", "ACTION_REQUIRED", "severity", "HIGH"),
        pushTo(event, readerToken).data());
  }

  @Test
  void withoutAMessageTheBodyIsTheLineAlone() {
    var event = publish(MERGE_OR_HOLD, null);
    dispatcher.dispatchPending();

    assertEquals("Tap to answer · Merge or Hold", pushTo(event, ownerToken).body());
    assertNull(pushTo(event, readerToken).body());
  }

  @Test
  void aTypedQuestionAndAMultipleChoiceHaveTheirOwnLines() {
    var typed = publish("{\"text\": \"REQUIRED\"}", null);
    var multiple =
        publish(
            """
            {"multiple": true, "choices": [{"id": "a", "label": "Unit tests"},
                                           {"id": "b", "label": "Lint"}]}
            """,
            null);
    dispatcher.dispatchPending();

    assertEquals("Tap to answer", pushTo(typed, ownerToken).body());
    assertEquals("Tap to answer · pick one or more", pushTo(multiple, ownerToken).body());
  }

  @Test
  void theOtherRowIsNotNamedOrCountedAndTheMessageIsStillShortened() {
    var event =
        publish(
            """
            {"text": "OPTIONAL", "textStyle": "OTHER",
             "choices": [{"id": "merge", "label": "Merge"}, {"id": "hold", "label": "Hold"}]}
            """,
            "x".repeat(900));
    dispatcher.dispatchPending();

    var body = pushTo(event, ownerToken).body();
    assertEquals("Tap to answer · Merge or Hold\n", body.substring(0, 30));
    assertEquals(EventPushMessages.MAX_BODY_LENGTH, body.substring(30).length());
  }

  @Test
  void anEventThatAsksNothingIsPushedAsBefore() {
    var event =
        UUID.fromString(
            asProducer(producer.apiKey())
                .contentType(ContentType.JSON)
                .body(
                    "{\"category\": \"INFO\", \"severity\": \"LOW\", \"title\": \"Deployed\", \"message\": \"v1.2\"}")
                .post(EVENTS)
                .then()
                .statusCode(201)
                .extract()
                .path("id"));
    dispatcher.dispatchPending();

    assertEquals("v1.2", pushTo(event, ownerToken).body());
  }
}
