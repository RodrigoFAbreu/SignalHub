package io.github.rodrigofabreu.signalhub.push;

import static io.github.rodrigofabreu.signalhub.TestClients.CLIENT;
import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asProducer;
import static org.junit.jupiter.api.Assertions.assertEquals;

import io.github.rodrigofabreu.signalhub.TestClients;
import io.github.rodrigofabreu.signalhub.TestProducers;
import io.github.rodrigofabreu.signalhub.event.Category;
import io.github.rodrigofabreu.signalhub.event.Severity;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import jakarta.inject.Inject;
import java.time.Duration;
import java.util.UUID;
import org.junit.jupiter.api.Test;

/** Publishing an event pushes it to the owner's clients, after the event is stored. */
@QuarkusTest
class EventPushTest {

  @Inject RecordingPushProvider provider;

  @Test
  void publishingAnEventPushesItToRegisteredClients() throws InterruptedException {
    var token = "ok-" + UUID.randomUUID();
    var client = TestClients.register("event-push");
    asClient(client.clientKey())
        .contentType(ContentType.JSON)
        .body(
            "{\"provider\": \"" + RecordingPushProvider.NAME + "\", \"token\": \"" + token + "\"}")
        .put(CLIENT + "/push-target")
        .then()
        .statusCode(200);
    var producer = TestProducers.register("event-push");

    String id =
        asProducer(producer.apiKey())
            .contentType(ContentType.JSON)
            .body(
                """
                {"category": "ACTION_REQUIRED", "severity": "CRITICAL",
                 "title": "Approve release", "message": "v2 is waiting."}
                """)
            .post("/api/v1/events")
            .then()
            .statusCode(201)
            .extract()
            .path("id");

    var eventId = UUID.fromString(id);
    assertEquals(
        new PushMessage(
            eventId,
            Category.ACTION_REQUIRED,
            Severity.CRITICAL,
            "Approve release",
            "v2 is waiting."),
        provider.await(token, eventId, Duration.ofSeconds(10)));
  }
}
