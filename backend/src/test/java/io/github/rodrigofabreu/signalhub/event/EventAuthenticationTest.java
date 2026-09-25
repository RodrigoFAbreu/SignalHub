package io.github.rodrigofabreu.signalhub.event;

import static io.github.rodrigofabreu.signalhub.TestProducers.ADMIN;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.github.rodrigofabreu.signalhub.TestProducers.asProducer;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.empty;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.hasItem;

import io.github.rodrigofabreu.signalhub.TestProducers;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import io.restassured.response.ValidatableResponse;
import io.restassured.specification.RequestSpecification;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/** Publishing requires a valid producer API key, and the event is bound to that producer. */
@QuarkusTest
class EventAuthenticationTest {

  private static final String EVENTS = EventApiTest.EVENTS;
  private static final String EVENT = EventApiTest.MINIMAL_EVENT;

  @Test
  void validKeyPublishesAnEventBoundToItsProducer() {
    var producer = TestProducers.register("auth-valid");

    String id =
        publish(asProducer(producer.apiKey()), EVENT)
            .statusCode(201)
            .body("producer.id", equalTo(producer.id().toString()))
            .body("producer.name", equalTo(producer.name()))
            .extract()
            .path("id");

    given()
        .when()
        .get(EVENTS + "/" + id)
        .then()
        .statusCode(200)
        .body("producer.id", equalTo(producer.id().toString()))
        .body("producer.name", equalTo(producer.name()));
  }

  @Test
  void missingKeyIsRejected() {
    expectUnauthorized(publish(given(), EVENT));
  }

  @ParameterizedTest
  @ValueSource(
      strings = {
        "",
        "Bearer",
        "Bearer ",
        "Bearer  shpk1_x",
        "Basic dXNlcjpwYXNz",
        "Token abc",
        "shpk1_00000000000000000000000000000000_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
      })
  void malformedAuthorizationHeaderIsRejected(String header) {
    expectUnauthorized(publish(given().header("Authorization", header), EVENT));
  }

  @Test
  void wrongSecretIsRejected() {
    var producer = TestProducers.register("auth-wrong-secret");
    var key = producer.apiKey();
    var tampered = key.substring(0, key.length() - 1) + (key.endsWith("A") ? "B" : "A");

    expectUnauthorized(publish(asProducer(tampered), EVENT));
  }

  @Test
  void unknownKeyIdIsRejected() {
    var key = TestProducers.register("auth-unknown-id").apiKey();
    // Same secret, different key ID. The secret may itself contain '_', so cut by position.
    var otherId = "shpk1_" + "0".repeat(32) + key.substring(38);

    expectUnauthorized(publish(asProducer(otherId), EVENT));
  }

  @ParameterizedTest
  @ValueSource(strings = {"not-a-key", "shpk1_", "shpk2_whatever"})
  void keyInTheWrongFormatIsRejected(String key) {
    expectUnauthorized(publish(asProducer(key), EVENT));
  }

  @Test
  void schemeIsCaseInsensitive() {
    var producer = TestProducers.register("auth-scheme-case");

    publish(given().header("Authorization", "bearer " + producer.apiKey()), EVENT).statusCode(201);
  }

  @Test
  void unauthenticatedRequestIsRejectedBeforeItsBodyIsRead() {
    expectUnauthorized(publish(given(), "{not json"));
    expectUnauthorized(publish(given(), "{\"title\": 42}"));
  }

  @Test
  void disabledProducerIsRejectedUntilEnabled() {
    var producer = TestProducers.register("auth-disabled");
    publish(asProducer(producer.apiKey()), EVENT).statusCode(201);

    asAdmin().post(ADMIN + "/" + producer.id() + "/disable").then().statusCode(200);
    expectUnauthorized(publish(asProducer(producer.apiKey()), EVENT));

    asAdmin().post(ADMIN + "/" + producer.id() + "/enable").then().statusCode(200);
    publish(asProducer(producer.apiKey()), EVENT).statusCode(201);
  }

  @Test
  void revokedKeyIsRejected() {
    var producer = TestProducers.register("auth-revoked");
    publish(asProducer(producer.apiKey()), EVENT).statusCode(201);

    revoke(producer.id().toString(), producer.keyId().toString());

    expectUnauthorized(publish(asProducer(producer.apiKey()), EVENT));
  }

  @Test
  void rotationKeepsBothKeysValidUntilTheOldOneIsRevoked() {
    var producer = TestProducers.register("auth-rotation");
    String newKey =
        asAdmin()
            .post(ADMIN + "/" + producer.id() + "/keys")
            .then()
            .statusCode(201)
            .extract()
            .path("apiKey");

    publish(asProducer(producer.apiKey()), EVENT).statusCode(201);
    publish(asProducer(newKey), EVENT)
        .statusCode(201)
        .body("producer.id", equalTo(producer.id().toString()));

    revoke(producer.id().toString(), producer.keyId().toString());

    expectUnauthorized(publish(asProducer(producer.apiKey()), EVENT));
    publish(asProducer(newKey), EVENT).statusCode(201);
  }

  @Test
  void payloadCannotClaimAProducerIdentity() {
    var producer = TestProducers.register("auth-spoof");
    var victim = TestProducers.register("auth-victim");

    for (var claim :
        new String[] {
          "\"source\": \"" + victim.name() + "\"",
          "\"producer\": {\"id\": \"" + victim.id() + "\", \"name\": \"" + victim.name() + "\"}",
          "\"producerId\": \"" + victim.id() + "\""
        }) {
      publish(asProducer(producer.apiKey()), EVENT.replace("{", "{" + claim + ","))
          .statusCode(400)
          .body("violations.field", hasItem(claim.substring(1, claim.indexOf('"', 1))));
    }
  }

  @Test
  void adminTokenIsNotAProducerKey() {
    expectUnauthorized(publish(asProducer(TestProducers.adminToken()), EVENT));
  }

  @Test
  void readingAnEventDoesNotNeedAKey() {
    var producer = TestProducers.register("auth-read");
    String id = publish(asProducer(producer.apiKey()), EVENT).statusCode(201).extract().path("id");

    given().when().get(EVENTS + "/" + id).then().statusCode(200);
  }

  private static void revoke(String producerId, String keyId) {
    asAdmin().post(ADMIN + "/" + producerId + "/keys/" + keyId + "/revoke").then().statusCode(200);
  }

  private static ValidatableResponse publish(RequestSpecification request, String body) {
    return request.contentType(ContentType.JSON).body(body).when().post(EVENTS).then();
  }

  /** Every failure looks the same, so callers learn nothing about which check failed. */
  private static void expectUnauthorized(ValidatableResponse response) {
    response
        .statusCode(401)
        .header("WWW-Authenticate", "Bearer realm=\"signalhub\"")
        .body("title", equalTo("Unauthorized"))
        .body("status", equalTo(401))
        .body("violations", empty());
  }
}
