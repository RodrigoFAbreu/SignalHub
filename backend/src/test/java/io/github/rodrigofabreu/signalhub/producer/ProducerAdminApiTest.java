package io.github.rodrigofabreu.signalhub.producer;

import static io.github.rodrigofabreu.signalhub.TestProducers.ADMIN;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.restassured.RestAssured.given;
import static org.hamcrest.MatcherAssert.assertThat;
import static org.hamcrest.Matchers.endsWith;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.hasKey;
import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.matchesPattern;
import static org.hamcrest.Matchers.not;
import static org.hamcrest.Matchers.notNullValue;
import static org.hamcrest.Matchers.nullValue;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.github.rodrigofabreu.signalhub.TestProducers;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import io.restassured.response.ValidatableResponse;
import io.restassured.specification.RequestSpecification;
import java.util.Arrays;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/** The producer management API: registration, keys, disabling, and its admin-token guard. */
@QuarkusTest
class ProducerAdminApiTest {

  private static final String KEY_FORMAT = "shpk1_[0-9a-f]{32}_[A-Za-z0-9_-]{43}";

  @Test
  void createRegistersTheProducerAndShowsItsFirstKeyOnce() {
    var name = "admin-create-" + UUID.randomUUID();
    var created =
        create(name)
            .statusCode(201)
            .contentType(ContentType.JSON)
            .body("producer.name", equalTo(name))
            .body("producer.createdAt", notNullValue())
            .body("producer.disabledAt", nullValue())
            .body("producer.keys", hasSize(1))
            .body("producer.keys[0].revokedAt", nullValue())
            .body("apiKey", matchesPattern(KEY_FORMAT))
            .extract();

    String id = created.path("producer.id");
    String keyId = created.path("keyId");
    String apiKey = created.path("apiKey");
    assertEquals(7, UUID.fromString(id).version(), "producer IDs are UUIDv7");
    assertEquals(keyId, created.path("producer.keys[0].id"));
    assertEquals(keyId.replace("-", ""), apiKey.substring(6, 38), "the key embeds its ID");
    assertThat(created.header("Location"), endsWith(ADMIN + "/" + id));

    // Never shown again.
    asAdmin()
        .get(ADMIN + "/" + id)
        .then()
        .statusCode(200)
        .body("name", equalTo(name))
        .body("keys[0].id", equalTo(keyId))
        .body("$", not(hasKey("apiKey")))
        .body("keys[0]", not(hasKey("apiKey")));
    asAdmin().get(ADMIN).then().statusCode(200).body("items.id", hasItem(id));
    var listed = asAdmin().get(ADMIN).then().statusCode(200).extract().asString();
    assertTrue(listed.contains(id));
    assertTrue(!listed.contains(apiKey), "listing must not reveal keys");
  }

  @Test
  void duplicateNameIsAConflict() {
    var name = "admin-duplicate-" + UUID.randomUUID();
    create(name).statusCode(201);

    create(name)
        .statusCode(409)
        .body("title", equalTo("Producer name already exists"))
        .body("violations[0].field", equalTo("name"));
  }

  @ParameterizedTest
  @ValueSource(strings = {"{}", "{\"name\": \"\"}", "{\"name\": \"has space\"}", "{\"name\": 42}"})
  void invalidNameIsRejected(String body) {
    asAdmin()
        .contentType(ContentType.JSON)
        .body(body)
        .post(ADMIN)
        .then()
        .statusCode(400)
        .body("violations[0].field", equalTo("name"));
  }

  @Test
  void nameLengthIsBounded() {
    create("n".repeat(100)).statusCode(201);
    create("n".repeat(101)).statusCode(400).body("violations[0].field", equalTo("name"));
  }

  @Test
  void clientCannotChooseTheProducerIdOrKey() {
    asAdmin()
        .contentType(ContentType.JSON)
        .body("{\"name\": \"admin-id\", \"id\": \"" + UUID.randomUUID() + "\"}")
        .post(ADMIN)
        .then()
        .statusCode(400)
        .body("violations.field", hasItem("id"));
  }

  @Test
  void issuingAKeyAddsOneAndKeepsTheOthersValid() {
    var producer = TestProducers.register("admin-issue");

    var issued =
        asAdmin()
            .post(ADMIN + "/" + producer.id() + "/keys")
            .then()
            .statusCode(201)
            .body("apiKey", matchesPattern(KEY_FORMAT))
            .body("producer.keys", hasSize(2))
            .body("producer.keys.revokedAt", equalTo(Arrays.asList(null, null)))
            .extract();

    String apiKey = issued.path("apiKey");
    String keyId = issued.path("keyId");
    assertNotEquals(producer.apiKey(), apiKey);
    assertEquals(keyId, issued.path("producer.keys[1].id"), "oldest first");
  }

  @Test
  void revokingAKeyIsPermanentAndIdempotent() {
    var producer = TestProducers.register("admin-revoke");
    var path = ADMIN + "/" + producer.id() + "/keys/" + producer.keyId() + "/revoke";

    String revokedAt =
        asAdmin()
            .post(path)
            .then()
            .statusCode(200)
            .body("keys[0].revokedAt", notNullValue())
            .extract()
            .path("keys[0].revokedAt");

    asAdmin().post(path).then().statusCode(200).body("keys[0].revokedAt", equalTo(revokedAt));
  }

  @Test
  void aKeyCanOnlyBeRevokedThroughItsOwnProducer() {
    var owner = TestProducers.register("admin-owner");
    var other = TestProducers.register("admin-other");

    asAdmin()
        .post(ADMIN + "/" + other.id() + "/keys/" + owner.keyId() + "/revoke")
        .then()
        .statusCode(404);
    asAdmin().get(ADMIN + "/" + owner.id()).then().body("keys[0].revokedAt", nullValue());
  }

  @Test
  void disableAndEnableToggleTheProducer() {
    var producer = TestProducers.register("admin-disable");
    var path = ADMIN + "/" + producer.id();

    String disabledAt =
        asAdmin()
            .post(path + "/disable")
            .then()
            .statusCode(200)
            .body("disabledAt", notNullValue())
            .extract()
            .path("disabledAt");
    asAdmin()
        .post(path + "/disable")
        .then()
        .statusCode(200)
        .body("disabledAt", equalTo(disabledAt));

    asAdmin().post(path + "/enable").then().statusCode(200).body("disabledAt", nullValue());
    // Disabling does not revoke keys.
    asAdmin().get(path).then().body("keys[0].revokedAt", nullValue());
  }

  @Test
  void unknownProducerOrKeyIsNotFound() {
    var unknown = ADMIN + "/" + UUID.randomUUID();
    var producer = TestProducers.register("admin-unknown");

    asAdmin().get(unknown).then().statusCode(404);
    asAdmin().post(unknown + "/disable").then().statusCode(404);
    asAdmin().post(unknown + "/enable").then().statusCode(404);
    asAdmin().post(unknown + "/keys").then().statusCode(404);
    asAdmin()
        .post(ADMIN + "/" + producer.id() + "/keys/" + UUID.randomUUID() + "/revoke")
        .then()
        .statusCode(404);
  }

  @Test
  void listIsOrderedByName() {
    var suffix = UUID.randomUUID();
    create("admin-list-b-" + suffix).statusCode(201);
    create("admin-list-a-" + suffix).statusCode(201);

    List<String> names = asAdmin().get(ADMIN).then().statusCode(200).extract().path("items.name");
    assertEquals(names.stream().sorted().toList(), names);
  }

  @Test
  void everyManagementEndpointRequiresTheAdminToken() {
    var producer = TestProducers.register("admin-guard");
    var paths =
        List.of(
            "POST " + ADMIN,
            "GET " + ADMIN,
            "GET " + ADMIN + "/" + producer.id(),
            "POST " + ADMIN + "/" + producer.id() + "/disable",
            "POST " + ADMIN + "/" + producer.id() + "/enable",
            "POST " + ADMIN + "/" + producer.id() + "/keys",
            "POST " + ADMIN + "/" + producer.id() + "/keys/" + producer.keyId() + "/revoke");
    var wrongToken = "Bearer " + TestProducers.adminToken() + "x";

    for (var request : paths) {
      var method = request.substring(0, request.indexOf(' '));
      var path = request.substring(request.indexOf(' ') + 1);
      expectUnauthorized(
          given().contentType(ContentType.JSON).body("{\"name\": \"x\"}"), method, path);
      expectUnauthorized(
          given().header("Authorization", wrongToken).contentType(ContentType.JSON).body("{}"),
          method,
          path);
      expectUnauthorized(
          given()
              .header("Authorization", "Bearer " + producer.apiKey())
              .contentType(ContentType.JSON)
              .body("{}"),
          method,
          path);
    }
    // Nothing changed.
    asAdmin()
        .get(ADMIN + "/" + producer.id())
        .then()
        .body("disabledAt", nullValue())
        .body("keys", hasSize(1))
        .body("keys[0].revokedAt", nullValue());
  }

  private static void expectUnauthorized(RequestSpecification request, String method, String path) {
    request
        .request(method, path)
        .then()
        .statusCode(401)
        .header("WWW-Authenticate", "Bearer realm=\"signalhub\"")
        .body("title", equalTo("Unauthorized"));
  }

  private static ValidatableResponse create(String name) {
    return asAdmin()
        .contentType(ContentType.JSON)
        .body("{\"name\": \"" + name + "\"}")
        .when()
        .post(ADMIN)
        .then();
  }
}
