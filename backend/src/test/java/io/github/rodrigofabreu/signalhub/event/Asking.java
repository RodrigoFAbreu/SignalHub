package io.github.rodrigofabreu.signalhub.event;

import static io.github.rodrigofabreu.signalhub.TestProducers.asProducer;

import io.github.rodrigofabreu.signalhub.TestProducers;
import io.restassured.http.ContentType;
import java.util.UUID;

/** Publishes events that ask, for the tests of questions and answers. */
final class Asking {

  static final String EVENTS = "/api/v1/events";

  /** A single-choice question with two choices, no text. */
  static final String MERGE_OR_HOLD =
      """
      {"choices": [{"id": "merge", "label": "Merge", "description": "Squash-merge now"},
                   {"id": "hold", "label": "Hold"}]}
      """;

  private Asking() {}

  static String event(String ask) {
    return """
        {"category": "ACTION_REQUIRED", "severity": "HIGH", "title": "Merge it?",
         "ask": %s}
        """
        .formatted(ask);
  }

  /** Publishes an event that asks, as the producer, and returns its ID. */
  static UUID publish(TestProducers.Registered producer, String ask) {
    return UUID.fromString(
        asProducer(producer.apiKey())
            .contentType(ContentType.JSON)
            .body(event(ask))
            .post(EVENTS)
            .then()
            .statusCode(201)
            .extract()
            .path("id"));
  }

  static String in(long seconds) {
    return java.time.Instant.now().plusSeconds(seconds).toString();
  }
}
