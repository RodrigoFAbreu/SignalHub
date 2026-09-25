package io.github.rodrigofabreu.signalhub.event;

import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static org.hamcrest.MatcherAssert.assertThat;
import static org.hamcrest.Matchers.empty;
import static org.hamcrest.Matchers.endsWith;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.startsWith;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import io.github.rodrigofabreu.signalhub.TestProducers;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import io.restassured.response.ValidatableResponse;
import jakarta.inject.Inject;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/** The {@code /api/v1/events} HTTP contract, end to end against real PostgreSQL. */
@QuarkusTest
class EventApiTest {

  static final String EVENTS = "/api/v1/events";

  static final String FULL_EVENT =
      """
      {
        "context": "signalhub",
        "category": "BLOCKED",
        "severity": "HIGH",
        "title": "Nightly build failed",
        "message": "3 of 412 tests failed on main.",
        "metadata": {"pipeline": "nightly", "run": 1842},
        "occurredAt": "2026-09-25T14:03:00+02:00"
      }
      """;

  static final String MINIMAL_EVENT =
      """
      {"category": "COMPLETED", "severity": "LOW", "title": "Backup done"}
      """;

  // One producer for the whole class; EventAuthenticationTest covers producers and keys.
  private static TestProducers.Registered producer;

  @Inject ObjectMapper json;

  @BeforeEach
  void registerProducer() {
    if (producer == null) {
      producer = TestProducers.register("event-api-test");
    }
  }

  @Test
  void createReturnsTheCanonicalEvent() {
    var created =
        post(FULL_EVENT)
            .statusCode(201)
            .contentType(ContentType.JSON)
            .body("producer.id", equalTo(producer.id().toString()))
            .body("producer.name", equalTo(producer.name()))
            .body("context", equalTo("signalhub"))
            .body("category", equalTo("BLOCKED"))
            .body("severity", equalTo("HIGH"))
            .body("title", equalTo("Nightly build failed"))
            .body("message", equalTo("3 of 412 tests failed on main."))
            .body("occurredAt", equalTo("2026-09-25T12:03:00Z"))
            .extract();

    String id = created.path("id");
    assertThat(created.header("Location"), endsWith(EVENTS + "/" + id));
  }

  @Test
  void idIsAServerGeneratedUuidV7() {
    var first = UUID.fromString(post(MINIMAL_EVENT).statusCode(201).extract().path("id"));
    var second = UUID.fromString(post(MINIMAL_EVENT).statusCode(201).extract().path("id"));

    assertEquals(7, first.version());
    assertNotEquals(first, second, "identical submissions are distinct events");
  }

  @Test
  void producerCannotSupplyServerOwnedFields() {
    var withId = FULL_EVENT.replace("{", "{\"id\": \"" + UUID.randomUUID() + "\",");
    var withCreatedAt = FULL_EVENT.replace("{", "{\"createdAt\": \"2020-01-01T00:00:00Z\",");

    post(withId).statusCode(400).body("violations.field", hasItem("id"));
    post(withCreatedAt).statusCode(400).body("violations.field", hasItem("createdAt"));
  }

  @Test
  void createdAtIsTheServerTime() {
    var before = Instant.now().truncatedTo(ChronoUnit.MICROS);
    String createdAt = post(MINIMAL_EVENT).statusCode(201).extract().path("createdAt");
    var after = Instant.now();

    var stored = Instant.parse(createdAt);
    assertFalse(stored.isBefore(before), stored + " is before the request");
    assertFalse(stored.isAfter(after), stored + " is after the response");
  }

  @Test
  void getReturnsExactlyWhatCreateReturned() throws Exception {
    var created = post(FULL_EVENT).statusCode(201).extract().asString();
    String id = json.readTree(created).get("id").asText();

    var fetched =
        asAdmin().when().get(EVENTS + "/" + id).then().statusCode(200).extract().asString();

    assertEquals(json.readTree(created), json.readTree(fetched));
  }

  @Test
  void optionalFieldsDefaultToNullAndMetadataToAnEmptyObject() {
    post(MINIMAL_EVENT)
        .statusCode(201)
        .body("context", equalTo(null))
        .body("message", equalTo(null))
        .body("occurredAt", equalTo(null))
        .body("metadata.size()", equalTo(0));
  }

  @Test
  void unknownIdIsNotFound() {
    asAdmin()
        .when()
        .get(EVENTS + "/" + UUID.randomUUID())
        .then()
        .statusCode(404)
        .body("title", equalTo("Event not found"))
        .body("status", equalTo(404))
        .body("violations", empty());
  }

  @Test
  void malformedIdIsNotFound() {
    asAdmin().when().get(EVENTS + "/not-a-uuid").then().statusCode(404);
  }

  @Test
  void requiredFieldsAreReportedTogether() {
    post("{}")
        .statusCode(400)
        .body("title", equalTo("Invalid request"))
        .body("status", equalTo(400))
        .body("violations.field", equalTo(List.of("category", "severity", "title")));
  }

  @Test
  void missingOrNullBodyIsRejected() {
    TestProducers.asProducer(producer.apiKey())
        .contentType(ContentType.JSON)
        .when()
        .post(EVENTS)
        .then()
        .statusCode(400);
    post("null").statusCode(400).body("violations[0].field", equalTo(""));
  }

  @Test
  void blankTitleIsRejected() {
    post(MINIMAL_EVENT.replace("\"Backup done\"", "\"   \""))
        .statusCode(400)
        .body("violations[0].field", equalTo("title"))
        .body("violations[0].message", equalTo("must not be blank"));
  }

  @Test
  void textLengthsAreBounded() {
    post(MINIMAL_EVENT.replace("Backup done", "t".repeat(200))).statusCode(201);
    post(MINIMAL_EVENT.replace("Backup done", "t".repeat(201)))
        .statusCode(400)
        .body("violations[0].field", equalTo("title"));
    post(FULL_EVENT.replace("signalhub", "c".repeat(201)))
        .statusCode(400)
        .body("violations[0].field", equalTo("context"));
    post(FULL_EVENT.replace("3 of 412 tests failed on main.", "m".repeat(4001)))
        .statusCode(400)
        .body("violations[0].field", equalTo("message"));
  }

  @ParameterizedTest
  @ValueSource(strings = {"-leading-dash", "has space", "emoji-🚀", ""})
  void contextMustBeAnIdentifier(String context) {
    post(FULL_EVENT.replace("signalhub", context))
        .statusCode(400)
        .body("violations[0].field", equalTo("context"));
  }

  @Test
  void nulCharactersAreRejected() {
    post(MINIMAL_EVENT.replace("Backup done", "Backup\\u0000done"))
        .statusCode(400)
        .body("violations[0].field", equalTo("title"));
  }

  @ParameterizedTest
  @ValueSource(strings = {"\"info\"", "\"URGENT\"", "0", "null"})
  void categoryMustBeAKnownValue(String category) {
    var expected =
        category.equals("null")
            ? "must not be null"
            : "must be one of [ACTION_REQUIRED, BLOCKED, COMPLETED, INFO]";
    post(MINIMAL_EVENT.replace("\"COMPLETED\"", category))
        .statusCode(400)
        .body("violations[0].field", equalTo("category"))
        .body("violations[0].message", equalTo(expected));
  }

  @Test
  void severityMustBeAKnownValue() {
    post(MINIMAL_EVENT.replace("\"LOW\"", "\"MEDIUM\""))
        .statusCode(400)
        .body("violations[0].field", equalTo("severity"))
        .body("violations[0].message", equalTo("must be one of [LOW, NORMAL, HIGH, CRITICAL]"));
  }

  @Test
  void allCategoriesAndSeveritiesAreAccepted() {
    for (var category : Category.values()) {
      for (var severity : Severity.values()) {
        post(MINIMAL_EVENT
                .replace("COMPLETED", category.name())
                .replace("\"LOW\"", "\"" + severity.name() + "\""))
            .statusCode(201)
            .body("category", equalTo(category.name()))
            .body("severity", equalTo(severity.name()));
      }
    }
  }

  @Test
  void textFieldsMustBeJsonStrings() {
    post(MINIMAL_EVENT.replace("\"Backup done\"", "42"))
        .statusCode(400)
        .body("violations[0].field", equalTo("title"))
        .body("violations[0].message", equalTo("must be a JSON string"));
  }

  @Test
  void occurredAtIsNormalizedToUtcAndTruncatedToMicroseconds() {
    post(withOccurredAt("\"2026-09-25T14:03:00.123456789-03:30\""))
        .statusCode(201)
        .body("occurredAt", equalTo("2026-09-25T17:33:00.123456Z"));
  }

  @ParameterizedTest
  @ValueSource(
      strings = {
        "\"2026-09-25T14:03:00\"", // no offset: ambiguous
        "\"2026-09-25\"",
        "\"yesterday\"",
        "1790345000", // epoch seconds: not accepted
        "{}"
      })
  void occurredAtMustBeIsoWithOffset(String occurredAt) {
    post(withOccurredAt(occurredAt))
        .statusCode(400)
        .body("violations[0].field", equalTo("occurredAt"))
        .body(
            "violations[0].message",
            equalTo("must be an ISO-8601 timestamp with a UTC offset, e.g. 2026-09-25T12:03:00Z"));
  }

  @Test
  void occurredAtMustHaveAFourDigitYear() {
    post(withOccurredAt("\"+10000-01-01T00:00:00Z\""))
        .statusCode(400)
        .body("violations[0].field", equalTo("occurredAt"))
        .body("violations[0].message", equalTo("year must be between 0001 and 9999"));
  }

  @Test
  void occurredAtIsIndependentOfCreatedAt() {
    var created = post(withOccurredAt("\"2001-01-01T00:00:00Z\"")).statusCode(201).extract();

    assertEquals("2001-01-01T00:00:00Z", created.path("occurredAt"));
    assertTrue(
        Instant.parse(created.path("createdAt")).isAfter(Instant.parse("2026-01-01T00:00:00Z")));
  }

  @Test
  void metadataRoundTripsUnchanged() throws Exception {
    var metadata =
        """
        {
          "string": "héllo \\"wörld\\" 🚀",
          "integer": 123456789012345678901234567890,
          "decimal": 3.141592653589793238462643383279,
          "negative": -0.5,
          "boolean": false,
          "null": null,
          "array": [1, "two", {"three": [3]}],
          "nested": {"deeper": {"deepest": {}}},
          "": "empty key"
        }
        """;
    var created = post(withMetadata(metadata)).statusCode(201).extract().asString();
    String id = json.readTree(created).get("id").asText();
    var fetched =
        asAdmin().when().get(EVENTS + "/" + id).then().statusCode(200).extract().asString();

    var expected = json.readTree(metadata);
    assertEquals(expected, json.readTree(created).get("metadata"));
    assertEquals(expected, json.readTree(fetched).get("metadata"));
    // Exact decimal and integer digits survive: nothing passes through a double or long.
    assertTrue(fetched.contains("3.141592653589793238462643383279"), fetched);
    assertTrue(fetched.contains("123456789012345678901234567890"), fetched);
  }

  @ParameterizedTest
  @ValueSource(strings = {"[1, 2]", "\"text\"", "42", "true"})
  void metadataMustBeAnObject(String metadata) {
    post(withMetadata(metadata))
        .statusCode(400)
        .body("violations[0].field", equalTo("metadata"))
        .body("violations[0].message", equalTo("must be a JSON object"));
  }

  @Test
  void metadataIsLimitedTo16KiB() throws Exception {
    var envelope = "{\"k\":\"\"}".length();
    var atLimit = metadataOfSize(ValidMetadata.MAX_BYTES - envelope);
    var overLimit = metadataOfSize(ValidMetadata.MAX_BYTES - envelope + 1);
    assertEquals(ValidMetadata.MAX_BYTES, atLimit.toString().length());

    post(withMetadata(atLimit.toString())).statusCode(201);
    post(withMetadata(overLimit.toString()))
        .statusCode(400)
        .body("violations[0].field", equalTo("metadata"))
        .body(
            "violations[0].message",
            equalTo("must be at most 16384 bytes when encoded as compact UTF-8 JSON"));
  }

  @ParameterizedTest
  @ValueSource(
      strings = {
        "{\"text\": \"a\\u0000b\"}",
        "{\"a\\u0000b\": 1}",
        "{\"huge\": 1e999999}",
        "{\"tiny\": 1e-999999}"
      })
  void metadataMustBeStorableInPostgres(String metadata) {
    post(withMetadata(metadata)).statusCode(400).body("violations[0].field", equalTo("metadata"));
  }

  @Test
  void malformedJsonIsRejected() {
    post("{\"title\": ")
        .statusCode(400)
        .body("violations[0].field", equalTo(""))
        .body("violations[0].message", startsWith("body is not valid JSON"));
  }

  @Test
  void excessiveNestingIsRejected() {
    var deep = "[".repeat(2000) + "]".repeat(2000);
    post(withMetadata("{\"deep\": " + deep + "}")).statusCode(400);
  }

  @Test
  void bodiesOver64KiBAreRejected() {
    var body = withMetadata("{\"k\": \"" + "x".repeat(64 * 1024) + "\"}");
    post(body).statusCode(413);
  }

  @Test
  void onlyJsonIsAccepted() {
    TestProducers.asProducer(producer.apiKey())
        .contentType(ContentType.TEXT)
        .body("hello")
        .when()
        .post(EVENTS)
        .then()
        .statusCode(415);
  }

  private static ValidatableResponse post(String body) {
    return TestProducers.asProducer(producer.apiKey())
        .contentType(ContentType.JSON)
        .body(body)
        .when()
        .post(EVENTS)
        .then();
  }

  private static String withOccurredAt(String occurredAt) {
    return MINIMAL_EVENT.replace("}", ", \"occurredAt\": " + occurredAt + "}");
  }

  private static String withMetadata(String metadata) {
    return MINIMAL_EVENT.replace("}", ", \"metadata\": " + metadata + "}");
  }

  private ObjectNode metadataOfSize(int valueLength) {
    return json.createObjectNode().put("k", "x".repeat(valueLength));
  }
}
