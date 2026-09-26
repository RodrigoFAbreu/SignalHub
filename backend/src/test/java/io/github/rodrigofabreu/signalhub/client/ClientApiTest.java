package io.github.rodrigofabreu.signalhub.client;

import static io.github.rodrigofabreu.signalhub.TestClients.ADMIN;
import static io.github.rodrigofabreu.signalhub.TestClients.CLIENT;
import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.github.rodrigofabreu.signalhub.TestProducers.asProducer;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.everyItem;
import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.hasKey;
import static org.hamcrest.Matchers.not;
import static org.hamcrest.Matchers.notNullValue;
import static org.hamcrest.Matchers.nullValue;
import static org.hamcrest.Matchers.startsWith;

import io.github.rodrigofabreu.signalhub.TestClients;
import io.github.rodrigofabreu.signalhub.TestProducers;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import io.restassured.response.ValidatableResponse;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/** Client registration, authentication and push targets, against real PostgreSQL. */
@QuarkusTest
class ClientApiTest {

  private static final String PUSH_TARGET = CLIENT + "/push-target";
  private static final String EVENTS = "/api/v1/events";

  @Test
  void registeringAClientIssuesItsKeyOnce() {
    var created =
        asAdmin()
            .contentType(ContentType.JSON)
            .body("{\"name\": \"Pixel 8\"}")
            .post(ADMIN)
            .then()
            .statusCode(201)
            .header("Location", containsString(ADMIN + "/"))
            .body("client.name", equalTo("Pixel 8"))
            .body("client.createdAt", notNullValue())
            .body("client.revokedAt", nullValue())
            .body("client.pushTarget", nullValue())
            .body("clientKey", startsWith("shck1_"))
            .extract();
    String id = created.path("client.id");

    given()
        .header("Authorization", "Bearer " + TestProducers.adminToken())
        .get(created.header("Location"))
        .then()
        .statusCode(200)
        .body("id", equalTo(id))
        .body("$", not(hasKey("clientKey")));
    asAdmin().get(ADMIN).then().statusCode(200).body("items.id", hasItem(id));
  }

  @ParameterizedTest
  @ValueSource(strings = {"{}", "{\"name\": \" \"}", "{\"name\": \"a\\u0000b\"}", "{\"x\": 1}"})
  void invalidRegistrationsAreRejected(String body) {
    asAdmin().contentType(ContentType.JSON).body(body).post(ADMIN).then().statusCode(400);
  }

  @Test
  void aNameLongerThan100CharactersIsRejected() {
    asAdmin()
        .contentType(ContentType.JSON)
        .body("{\"name\": \"" + "x".repeat(101) + "\"}")
        .post(ADMIN)
        .then()
        .statusCode(400)
        .body("violations[0].field", equalTo("name"));
  }

  @Test
  void managementRequiresTheAdminToken() {
    var client = TestClients.register("mgmt-auth");
    var producer = TestProducers.register("client-mgmt");
    given().get(ADMIN).then().statusCode(401);
    asClient(client.clientKey()).get(ADMIN).then().statusCode(401);
    asProducer(producer.apiKey()).get(ADMIN).then().statusCode(401);
  }

  @Test
  void unknownClientsAreNotFound() {
    asAdmin().get(ADMIN + "/" + UUID.randomUUID()).then().statusCode(404);
    asAdmin().post(ADMIN + "/" + UUID.randomUUID() + "/revoke").then().statusCode(404);
  }

  @Test
  void aClientReadsItsOwnRegistration() {
    var client = TestClients.register("Laptop");
    asClient(client.clientKey())
        .get(CLIENT)
        .then()
        .statusCode(200)
        .body("id", equalTo(client.id().toString()))
        .body("name", equalTo("Laptop"));
  }

  @Test
  void clientEndpointsRequireAClientKey() {
    var producer = TestProducers.register("client-endpoint");
    given().get(CLIENT).then().statusCode(401).header("WWW-Authenticate", containsString("Bearer"));
    asAdmin().get(CLIENT).then().statusCode(401);
    asProducer(producer.apiKey()).get(CLIENT).then().statusCode(401);
    var client = TestClients.register("tampered");
    var tampered =
        client.clientKey().substring(0, 81) + (client.clientKey().endsWith("A") ? "B" : "A");
    asClient(tampered).get(CLIENT).then().statusCode(401);
    // Unauthenticated requests are rejected before the body is read.
    given().contentType(ContentType.JSON).body("not json").put(PUSH_TARGET).then().statusCode(401);
  }

  @Test
  void aClientSetsReplacesAndRemovesItsPushTarget() {
    var client = TestClients.register("push");
    setPushTarget(client, "fcm", "token-1")
        .statusCode(200)
        .body("pushTarget.provider", equalTo("fcm"))
        .body("pushTarget.updatedAt", notNullValue())
        // The token is write-only.
        .body("pushTarget", not(hasKey("token")));
    setPushTarget(client, "webpush", "token-2")
        .statusCode(200)
        .body("pushTarget.provider", equalTo("webpush"));
    asAdmin().get(ADMIN + "/" + client.id()).then().body("pushTarget.provider", equalTo("webpush"));

    asClient(client.clientKey())
        .delete(PUSH_TARGET)
        .then()
        .statusCode(200)
        .body("pushTarget", nullValue());
    // Removing a missing target changes nothing.
    asClient(client.clientKey()).delete(PUSH_TARGET).then().statusCode(200);
  }

  @Test
  void aPushTargetBelongsToOneClient() {
    var token = "shared-" + UUID.randomUUID();
    var old = TestClients.register("before-reinstall");
    var current = TestClients.register("after-reinstall");
    setPushTarget(old, "fcm", token).statusCode(200);

    setPushTarget(current, "fcm", token).statusCode(200);

    asClient(old.clientKey()).get(CLIENT).then().body("pushTarget", nullValue());
    asClient(current.clientKey()).get(CLIENT).then().body("pushTarget.provider", equalTo("fcm"));
  }

  @Test
  void theSameTokenFromAnotherProviderIsADifferentTarget() {
    var token = "same-" + UUID.randomUUID();
    var first = TestClients.register("provider-a");
    var second = TestClients.register("provider-b");
    setPushTarget(first, "fcm", token).statusCode(200);
    setPushTarget(second, "apns", token).statusCode(200);

    asClient(first.clientKey()).get(CLIENT).then().body("pushTarget.provider", equalTo("fcm"));
  }

  @ParameterizedTest
  @ValueSource(
      strings = {
        "{}",
        "{\"provider\": \"fcm\"}",
        "{\"token\": \"t\"}",
        "{\"provider\": \"FCM\", \"token\": \"t\"}",
        "{\"provider\": \"-fcm\", \"token\": \"t\"}",
        "{\"provider\": \"fcm\", \"token\": \" \"}",
        "{\"provider\": \"fcm\", \"token\": \"a\\u0000b\"}",
        "{\"provider\": \"fcm\", \"token\": 42}",
        "{\"provider\": \"fcm\", \"token\": \"t\", \"platform\": \"android\"}",
      })
  void invalidPushTargetsAreRejected(String body) {
    var client = TestClients.register("invalid-push");
    asClient(client.clientKey())
        .contentType(ContentType.JSON)
        .body(body)
        .put(PUSH_TARGET)
        .then()
        .statusCode(400);
  }

  @Test
  void pushTargetLengthsAreBounded() {
    var client = TestClients.register("push-bounds");
    setPushTarget(client, "p".repeat(50), "t".repeat(4096)).statusCode(200);
    setPushTarget(client, "p".repeat(51), "t").statusCode(400);
    setPushTarget(client, "fcm", "t".repeat(4097)).statusCode(400);
  }

  @Test
  void revokingAClientBlocksItsKeyAndDropsItsPushTarget() {
    var client = TestClients.register("revoked");
    setPushTarget(client, "fcm", "revoked-" + UUID.randomUUID()).statusCode(200);

    var revokedAt =
        asAdmin()
            .post(ADMIN + "/" + client.id() + "/revoke")
            .then()
            .statusCode(200)
            .body("revokedAt", notNullValue())
            .body("pushTarget", nullValue())
            .extract()
            .<String>path("revokedAt");

    asClient(client.clientKey()).get(CLIENT).then().statusCode(401);
    setPushTarget(client, "fcm", "again").statusCode(401);
    asClient(client.clientKey()).get(EVENTS).then().statusCode(401);
    // Revoking again changes nothing.
    asAdmin()
        .post(ADMIN + "/" + client.id() + "/revoke")
        .then()
        .statusCode(200)
        .body("revokedAt", equalTo(revokedAt));
  }

  @Test
  void aClientKeyReadsTheEventListing() {
    var client = TestClients.register("reader");
    var producer = TestProducers.register("client-read");
    String id =
        asProducer(producer.apiKey())
            .contentType(ContentType.JSON)
            .body("{\"category\": \"INFO\", \"severity\": \"LOW\", \"title\": \"For clients\"}")
            .post(EVENTS)
            .then()
            .statusCode(201)
            .extract()
            .path("id");

    asClient(client.clientKey())
        .queryParam("producerId", producer.id())
        .get(EVENTS)
        .then()
        .statusCode(200)
        .body("items.id", everyItem(equalTo(id)))
        .body("items.id", hasItem(id));
  }

  private static ValidatableResponse setPushTarget(
      TestClients.Registered client, String provider, String token) {
    return asClient(client.clientKey())
        .contentType(ContentType.JSON)
        .body("{\"provider\": \"" + provider + "\", \"token\": \"" + token + "\"}")
        .put(PUSH_TARGET)
        .then();
  }
}
