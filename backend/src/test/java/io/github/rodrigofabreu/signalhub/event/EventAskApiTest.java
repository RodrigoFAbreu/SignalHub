package io.github.rodrigofabreu.signalhub.event;

import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.github.rodrigofabreu.signalhub.TestProducers.asProducer;
import static io.github.rodrigofabreu.signalhub.event.Asking.EVENTS;
import static io.github.rodrigofabreu.signalhub.event.Asking.MERGE_OR_HOLD;
import static io.github.rodrigofabreu.signalhub.event.Asking.event;
import static org.hamcrest.Matchers.contains;
import static org.hamcrest.Matchers.empty;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.nullValue;

import io.github.rodrigofabreu.signalhub.TestProducers;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import io.restassured.response.ValidatableResponse;
import java.time.Instant;
import java.util.UUID;
import java.util.stream.Collectors;
import java.util.stream.IntStream;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

/** The optional {@code ask} of an event: what is accepted, how it is stored, and idempotency. */
@QuarkusTest
class EventAskApiTest {

  private ValidatableResponse publish(TestProducers.Registered producer, String body) {
    return asProducer(producer.apiKey())
        .contentType(ContentType.JSON)
        .body(body)
        .post(EVENTS)
        .then();
  }

  @Test
  void anEventWithoutAskBehavesAsBefore() {
    var producer = TestProducers.register("ask-none");

    publish(producer, "{\"category\": \"INFO\", \"severity\": \"LOW\", \"title\": \"Plain\"}")
        .statusCode(201)
        .body("ask", nullValue())
        .body("answer", nullValue())
        .body("answerState", nullValue())
        .body("closedBy", nullValue())
        .body("closedAt", nullValue())
        .body("closeNote", nullValue())
        .body("canAnswer", equalTo(false));
    publish(producer, event("null")).statusCode(201).body("ask", nullValue());
  }

  @Test
  void storesTheQuestionNormalizedWithItsDefaultsFilledIn() {
    var producer = TestProducers.register("ask-normal");
    var owner = ownerName(producer);

    publish(producer, event(MERGE_OR_HOLD))
        .statusCode(201)
        .body("ask.choices.id", contains("merge", "hold"))
        .body("ask.choices.label", contains("Merge", "Hold"))
        .body("ask.choices[0].description", equalTo("Squash-merge now"))
        .body("ask.choices[1].description", nullValue())
        .body("ask.multiple", equalTo(false))
        .body("ask.text", equalTo("NONE"))
        .body("ask.textStyle", nullValue())
        .body("ask.closesAt", nullValue())
        .body("ask.whoCanAnswer.name", contains(owner))
        .body("answerState", equalTo("OPEN"))
        .body("answer", nullValue())
        // The producer answers nothing, whatever it asked.
        .body("canAnswer", equalTo(false));
  }

  @Test
  void aTypedQuestionNeedsNoChoicesAndTakesRequiredText() {
    var producer = TestProducers.register("ask-typed");

    publish(producer, event("{}"))
        .statusCode(201)
        .body("ask.choices", empty())
        .body("ask.text", equalTo("REQUIRED"))
        .body("ask.textStyle", nullValue());
    publish(producer, event("{\"choices\": [], \"text\": \"REQUIRED\"}")).statusCode(201);
  }

  @Test
  void aNoteIsTheDefaultTextStyleOfAQuestionWithChoicesAndText() {
    var producer = TestProducers.register("ask-note");

    publish(
            producer,
            event("{\"choices\": [{\"id\": \"a\", \"label\": \"A\"}], \"text\": \"OPTIONAL\"}"))
        .statusCode(201)
        .body("ask.textStyle", equalTo("NOTE"));
    publish(
            producer,
            event(
                "{\"choices\": [{\"id\": \"a\", \"label\": \"A\"}], \"text\": \"OPTIONAL\","
                    + " \"textStyle\": \"OTHER\"}"))
        .statusCode(201)
        .body("ask.textStyle", equalTo("OTHER"));
  }

  @Test
  void anEmptyDescriptionIsStoredAsNone() {
    var producer = TestProducers.register("ask-empty-description");

    publish(
            producer,
            event("{\"choices\": [{\"id\": \"a\", \"label\": \"A\", \"description\": \"\"}]}"))
        .statusCode(201)
        .body("ask.choices[0].description", nullValue());
  }

  @Test
  void acceptsTheLimits() {
    var producer = TestProducers.register("ask-limits");
    var ten =
        IntStream.range(0, 10)
            .mapToObj(i -> "{\"id\": \"c" + i + "\", \"label\": \"Choice " + i + "\"}")
            .collect(Collectors.joining(","));
    var longChoice =
        "{\"id\": \"%s\", \"label\": \"%s\", \"description\": \"%s\"}"
            .formatted("i".repeat(64), "l".repeat(100), "d".repeat(1000));

    publish(producer, event("{\"choices\": [" + ten + "], \"multiple\": true}")).statusCode(201);
    publish(producer, event("{\"choices\": [" + longChoice + "]}")).statusCode(201);
    publish(producer, event("{\"closesAt\": \"" + Asking.in(30L * 24 * 3600 - 60) + "\"}"))
        .statusCode(201);
  }

  @ParameterizedTest
  @CsvSource(
      delimiter = '|',
      value = {
        // choices
        "{\"choices\": [{\"id\": \"a\", \"label\": \"A\"},{\"id\": \"a\", \"label\": \"B\"}]}|ask.choices[1].id",
        "{\"choices\": [{\"id\": \"-a\", \"label\": \"A\"}]}|ask.choices[0].id",
        "{\"choices\": [{\"label\": \"A\"}]}|ask.choices[0].id",
        "{\"choices\": [{\"id\": \"a\"}]}|ask.choices[0].label",
        "{\"choices\": [{\"id\": \"a\", \"label\": \"\"}]}|ask.choices[0].label",
        "{\"choices\": [{\"id\": \"a\", \"label\": \"  \"}]}|ask.choices[0].label",
        "{\"choices\": [{\"id\": \"a\", \"label\": \"A\\nB\"}]}|ask.choices[0].label",
        "{\"choices\": [{\"id\": \"a\", \"label\": \"A\"},{\"id\": \"b\", \"label\": \"a\"}]}|ask.choices[1].label",
        "{\"choices\": [{\"id\": \"a\", \"label\": \"A\", \"description\": \"x\\u0000\"}]}|ask.choices[0].description",
        "{\"choices\": [{\"id\": \"a\", \"label\": \"A\", \"extra\": 1}]}|ask.choices.[0].extra",
        "{\"choices\": [null]}|ask.choices[0]",
        // multiple
        "{\"choices\": [{\"id\": \"a\", \"label\": \"A\"}], \"multiple\": true}|ask.multiple",
        "{\"multiple\": true}|ask.multiple",
        "{\"multiple\": \"true\"}|ask.multiple",
        // text and text style
        "{\"text\": \"NONE\"}|ask.text",
        "{\"text\": \"OPTIONAL\"}|ask.text",
        "{\"text\": \"MAYBE\"}|ask.text",
        "{\"textStyle\": \"NOTE\"}|ask.textStyle",
        "{\"choices\": [{\"id\": \"a\", \"label\": \"A\"}], \"textStyle\": \"NOTE\"}|ask.textStyle",
        "{\"choices\": [{\"id\": \"a\", \"label\": \"A\"}], \"text\": \"NONE\", \"textStyle\": \"OTHER\"}|ask.textStyle",
        "{\"choices\": [{\"id\": \"a\", \"label\": \"A\"}], \"text\": \"REQUIRED\", \"textStyle\": \"OTHER\"}|ask.textStyle",
        "{\"choices\": [{\"id\": \"a\", \"label\": \"Other\"}], \"text\": \"OPTIONAL\", \"textStyle\": \"OTHER\"}|ask.choices[0].label",
        "{\"choices\": [{\"id\": \"a\", \"label\": \" other \"}], \"text\": \"OPTIONAL\", \"textStyle\": \"OTHER\"}|ask.choices[0].label",
        // response-only and unknown fields
        "{\"whoCanAnswer\": []}|ask.whoCanAnswer",
        "{\"unknown\": 1}|ask.unknown",
        // closesAt
        "{\"closesAt\": \"tomorrow\"}|ask.closesAt",
        "{\"closesAt\": \"2026-10-17T09:00:00\"}|ask.closesAt",
        "{\"closesAt\": 1792000000}|ask.closesAt",
      })
  void refusesAQuestionThatIsNotWellFormed(String ask, String field) {
    var producer = TestProducers.register("ask-bad");

    publish(producer, event(ask)).statusCode(400).body("violations.field", hasItem(field));
  }

  @Test
  void refusesMoreThanTenChoicesAndTooLongText() {
    var producer = TestProducers.register("ask-too-long");
    var eleven =
        IntStream.range(0, 11)
            .mapToObj(i -> "{\"id\": \"c" + i + "\", \"label\": \"Choice " + i + "\"}")
            .collect(Collectors.joining(","));

    publish(producer, event("{\"choices\": [" + eleven + "]}"))
        .statusCode(400)
        .body("violations.field", hasItem("ask.choices"));
    publish(
            producer,
            event("{\"choices\": [{\"id\": \"%s\", \"label\": \"A\"}]}".formatted("i".repeat(65))))
        .statusCode(400)
        .body("violations.field", hasItem("ask.choices[0].id"));
    publish(
            producer,
            event("{\"choices\": [{\"id\": \"a\", \"label\": \"%s\"}]}".formatted("l".repeat(101))))
        .statusCode(400)
        .body("violations.field", hasItem("ask.choices[0].label"));
    publish(
            producer,
            event(
                "{\"choices\": [{\"id\": \"a\", \"label\": \"A\", \"description\": \"%s\"}]}"
                    .formatted("d".repeat(1001))))
        .statusCode(400)
        .body("violations.field", hasItem("ask.choices[0].description"));
  }

  @Test
  void closesAtMustBeInTheFutureAndAtMostThirtyDaysAhead() {
    var producer = TestProducers.register("ask-closes");

    publish(producer, event("{\"closesAt\": \"" + Asking.in(-5) + "\"}"))
        .statusCode(400)
        .body("violations.field", hasItem("ask.closesAt"))
        .body("violations.message", hasItem("must be in the future"));
    publish(producer, event("{\"closesAt\": \"" + Asking.in(31L * 24 * 3600) + "\"}"))
        .statusCode(400)
        .body("violations.field", hasItem("ask.closesAt"))
        .body("violations.message", hasItem("must be at most 30 days ahead"));
  }

  @Test
  void closesAtIsKeptAsAUtcInstantTruncatedToMicroseconds() {
    var producer = TestProducers.register("ask-closes-utc");
    var closesAt = Instant.now().plusSeconds(3600).plusNanos(123_456_789);

    var stored =
        publish(
                producer,
                event(
                    "{\"closesAt\": \""
                        + closesAt.atOffset(java.time.ZoneOffset.ofHours(2))
                        + "\"}"))
            .statusCode(201)
            .extract()
            .<String>path("ask.closesAt");

    org.junit.jupiter.api.Assertions.assertEquals(
        closesAt.truncatedTo(java.time.temporal.ChronoUnit.MICROS), Instant.parse(stored));
  }

  @Test
  void aRetryOfAPublishedQuestionReturnsTheStoredEventEvenAfterItsClosesAtPassed() {
    var producer = TestProducers.register("ask-idempotent");
    var body = event("{\"closesAt\": \"" + Asking.in(2) + "\"}");

    var id =
        asProducer(producer.apiKey())
            .contentType(ContentType.JSON)
            .header("Idempotency-Key", "ask-1")
            .body(body)
            .post(EVENTS)
            .then()
            .statusCode(201)
            .extract()
            .<String>path("id");
    sleep(2200);

    asProducer(producer.apiKey())
        .contentType(ContentType.JSON)
        .header("Idempotency-Key", "ask-1")
        .body(body)
        .post(EVENTS)
        .then()
        .statusCode(200)
        .body("id", equalTo(id))
        .body("answerState", equalTo("CLOSED"))
        .body("closedBy", equalTo("TIME"));
  }

  @Test
  void theQuestionIsPartOfTheIdempotencyComparison() {
    var producer = TestProducers.register("ask-idempotent-diff");
    var key = "ask-" + UUID.randomUUID();
    asProducer(producer.apiKey())
        .contentType(ContentType.JSON)
        .header("Idempotency-Key", key)
        .body(event(MERGE_OR_HOLD))
        .post(EVENTS)
        .then()
        .statusCode(201);

    // The same question again is the same request.
    asProducer(producer.apiKey())
        .contentType(ContentType.JSON)
        .header("Idempotency-Key", key)
        .body(event(MERGE_OR_HOLD))
        .post(EVENTS)
        .then()
        .statusCode(200);
    // A different question, or none, is a different event.
    for (var other :
        new String[] {
          event("{\"choices\": [{\"id\": \"merge\", \"label\": \"Merge it\"}]}"), event("null"),
        }) {
      asProducer(producer.apiKey())
          .contentType(ContentType.JSON)
          .header("Idempotency-Key", key)
          .body(other)
          .post(EVENTS)
          .then()
          .statusCode(422);
    }
  }

  @Test
  void theOperatorsTestEventAcceptsAnAskAndValidatesItAsAProducer() {
    var producer = TestProducers.register("ask-operator");

    var id =
        asAdmin()
            .contentType(ContentType.JSON)
            .body(event(MERGE_OR_HOLD))
            .post(TestProducers.ADMIN + "/" + producer.id() + "/events")
            .then()
            .statusCode(201)
            .body("ask.choices.id", contains("merge", "hold"))
            .body("answerState", equalTo("OPEN"))
            .extract()
            .<String>path("id");

    asAdmin()
        .get(EVENTS + "/" + id)
        .then()
        .statusCode(200)
        .body("canAnswer", equalTo(false))
        .body("answerState", equalTo("OPEN"));
    asAdmin()
        .contentType(ContentType.JSON)
        .body(event("{\"closesAt\": \"" + Asking.in(-5) + "\"}"))
        .post(TestProducers.ADMIN + "/" + producer.id() + "/events")
        .then()
        .statusCode(400)
        .body("violations.field", hasItem("ask.closesAt"));
  }

  private static String ownerName(TestProducers.Registered producer) {
    return asAdmin()
        .get(TestProducers.ADMIN + "/" + producer.id())
        .then()
        .statusCode(200)
        .extract()
        .path("owner.name");
  }

  private static void sleep(long millis) {
    try {
      Thread.sleep(millis);
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      throw new IllegalStateException(e);
    }
  }
}
