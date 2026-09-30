package io.github.rodrigofabreu.signalhub.event;

import static io.github.rodrigofabreu.signalhub.TestClients.CLIENT;
import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.github.rodrigofabreu.signalhub.TestProducers.asProducer;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.notNullValue;
import static org.hamcrest.Matchers.nullValue;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.github.rodrigofabreu.signalhub.TestClients;
import io.github.rodrigofabreu.signalhub.TestProducers;
import io.github.rodrigofabreu.signalhub.push.FakePushProvider;
import io.github.rodrigofabreu.signalhub.push.PushOutcome;
import io.micrometer.core.instrument.MeterRegistry;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import io.restassured.response.ValidatableResponse;
import io.restassured.specification.RequestSpecification;
import jakarta.inject.Inject;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * Sending an event as a producer with the admin token, against real PostgreSQL and the fake push
 * provider: stored under the producer, pushed through preferences as the producer's own, refused
 * for a disabled or unknown producer, validated as a producer's.
 */
@QuarkusTest
class OperatorEventApiTest {

  private static final String EVENTS = "/api/v1/events";

  @Inject EventPushDispatcher dispatcher;
  @Inject FakePushProvider fake;
  @Inject MeterRegistry registry;

  @BeforeEach
  void setUp() {
    // Events from other tests wait in the outbox too; send them before each test's own.
    dispatcher.dispatchPending();
    fake.answer((token, message) -> PushOutcome.delivered());
  }

  @Test
  void theEventIsStoredUnderTheChosenProducer() {
    var producer = TestProducers.register("operator-event");
    var body =
        Map.of(
            "context",
            "admin-page",
            "category",
            "ACTION_REQUIRED",
            "severity",
            "HIGH",
            "title",
            "Test event",
            "message",
            "Sent from the admin page.",
            "link",
            "https://example.com/test",
            "metadata",
            Map.of("test", true));
    var before = published();

    var created =
        send(asAdmin(), producer.id(), body)
            .statusCode(201)
            .body("producer.id", equalTo(producer.id().toString()))
            .body("producer.name", equalTo(producer.name()))
            .body("context", equalTo("admin-page"))
            .body("category", equalTo("ACTION_REQUIRED"))
            .body("severity", equalTo("HIGH"))
            .body("title", equalTo("Test event"))
            .body("message", equalTo("Sent from the admin page."))
            .body("link", equalTo("https://example.com/test"))
            .body("metadata.test", equalTo(true))
            .body("readAt", nullValue())
            .extract();

    var id = created.path("id").toString();
    assertTrue(created.header("Location").endsWith(EVENTS + "/" + id));
    assertEquals(before + 1, published());
    asAdmin()
        .get(EVENTS + "/" + id)
        .then()
        .statusCode(200)
        .body("producer.id", equalTo(producer.id().toString()));
    asAdmin()
        .queryParam("producerId", producer.id().toString())
        .get(EVENTS)
        .then()
        .statusCode(200)
        .body("items", hasSize(1))
        .body("items[0].id", equalTo(id));
    asAdmin()
        .get(TestProducers.ADMIN + "/" + producer.id())
        .then()
        .statusCode(200)
        .body("lastEventAt", equalTo(created.path("createdAt")));
  }

  @Test
  void theEventIsPushedThroughPreferencesAsTheProducersOwn() {
    var producer = TestProducers.register("operator-push");
    var everything = clientWithTarget("{}");
    var mutingProducer = clientWithTarget("{\"mutedProducerIds\": [\"" + producer.id() + "\"]}");
    var highOnly = clientWithTarget("{\"minimumSeverity\": \"HIGH\"}");
    var noInfo = clientWithTarget("{\"mutedCategories\": [\"INFO\"]}");
    var paused = clientWithTarget("{\"enabled\": false}");

    var info = sendEvent(producer.id(), "INFO", "NORMAL");
    var urgent = sendEvent(producer.id(), "ACTION_REQUIRED", "HIGH");
    dispatcher.dispatchPending();

    var clients = new String[] {everything, mutingProducer, highOnly, noInfo, paused};
    assertEquals(List.of(everything), recipientsOf(info, clients));
    assertEquals(List.of(everything, highOnly, noInfo), recipientsOf(urgent, clients));
    var message = sentFor(urgent, everything).get(0).message();
    assertEquals("Test ACTION_REQUIRED", message.title());
    assertEquals(
        Map.of("eventId", urgent.toString(), "category", "ACTION_REQUIRED", "severity", "HIGH"),
        message.data());
  }

  @Test
  void aDisabledProducerIsRefusedAndNothingIsStored() {
    var producer = TestProducers.register("operator-disabled");
    asAdmin().post(TestProducers.ADMIN + "/" + producer.id() + "/disable").then().statusCode(200);

    send(asAdmin(), producer.id(), minimal())
        .statusCode(409)
        .body("title", equalTo("Producer is disabled"))
        .body("status", equalTo(409));

    listOf(producer.id()).body("items", hasSize(0));
    asAdmin().post(TestProducers.ADMIN + "/" + producer.id() + "/enable").then().statusCode(200);
    send(asAdmin(), producer.id(), minimal()).statusCode(201);
  }

  @Test
  void anUnknownProducerIsNotFound() {
    send(asAdmin(), UUID.randomUUID(), minimal())
        .statusCode(404)
        .body("title", equalTo("Producer not found"));
    asAdmin()
        .contentType(ContentType.JSON)
        .body(minimal())
        .post(TestProducers.ADMIN + "/not-a-uuid/events")
        .then()
        .statusCode(404);
  }

  @Test
  void theEventIsValidatedAsAProducersIsAndNothingIsStored() {
    var producer = TestProducers.register("operator-invalid");
    var invalid =
        List.<Map<String, Object>>of(
            Map.of("category", "INFO", "severity", "LOW"),
            Map.of("category", "INFO", "severity", "LOW", "title", " "),
            Map.of("category", "NOPE", "severity", "LOW", "title", "x"),
            Map.of("category", "INFO", "severity", "LOW", "title", "x", "link", "ftp://x.test"),
            Map.of("category", "INFO", "severity", "LOW", "title", "x", "context", "has space"),
            // The producer comes from the path; the body cannot name another.
            Map.of("category", "INFO", "severity", "LOW", "title", "x", "producer", "other"));
    for (var body : invalid) {
      send(asAdmin(), producer.id(), body).statusCode(400).body("title", notNullValue());
    }
    asAdmin()
        .contentType(ContentType.JSON)
        .post(TestProducers.ADMIN + "/" + producer.id() + "/events")
        .then()
        .statusCode(400);

    listOf(producer.id()).body("items", hasSize(0));
  }

  @Test
  void theAdminTokenIsRequired() {
    var producer = TestProducers.register("operator-auth");
    send(given(), producer.id(), minimal()).statusCode(401);
    send(asProducer(producer.apiKey()), producer.id(), minimal()).statusCode(401);
    var client = TestClients.register("operator-auth-client");
    send(asClient(client.clientKey()), producer.id(), minimal()).statusCode(401);

    listOf(producer.id()).body("items", hasSize(0));
  }

  private UUID sendEvent(UUID producerId, String category, String severity) {
    var body = Map.of("category", category, "severity", severity, "title", "Test " + category);
    return UUID.fromString(send(asAdmin(), producerId, body).statusCode(201).extract().path("id"));
  }

  private static ValidatableResponse send(
      RequestSpecification request, UUID producerId, Map<String, ?> body) {
    return request
        .contentType(ContentType.JSON)
        .body(body)
        .post(TestProducers.ADMIN + "/" + producerId + "/events")
        .then();
  }

  private static Map<String, Object> minimal() {
    return Map.of("category", "INFO", "severity", "LOW", "title", "Test");
  }

  private static ValidatableResponse listOf(UUID producerId) {
    return asAdmin().queryParam("producerId", producerId.toString()).get(EVENTS).then();
  }

  private static String clientWithTarget(String preferences) {
    var client = TestClients.register("operator-push");
    var token = "operator-" + UUID.randomUUID();
    asClient(client.clientKey())
        .contentType(ContentType.JSON)
        .body(Map.of("provider", FakePushProvider.NAME, "token", token))
        .put(CLIENT + "/push-target")
        .then()
        .statusCode(200);
    asClient(client.clientKey())
        .contentType(ContentType.JSON)
        .body(preferences)
        .put(CLIENT + "/push-preferences")
        .then()
        .statusCode(200);
    return token;
  }

  private List<String> recipientsOf(UUID eventId, String... tokens) {
    return Arrays.stream(tokens).filter(token -> !sentFor(eventId, token).isEmpty()).toList();
  }

  private List<FakePushProvider.Sent> sentFor(UUID eventId, String token) {
    return fake.sent().stream()
        .filter(sent -> eventId.toString().equals(sent.message().data().get("eventId")))
        .filter(sent -> sent.token().equals(token))
        .toList();
  }

  private double published() {
    return registry.get("signalhub.events.published").counter().count();
  }
}
