package io.github.rodrigofabreu.signalhub.producer;

import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.adminToken;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.github.rodrigofabreu.signalhub.TestProducers.asProducer;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.empty;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.hasKey;
import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.not;
import static org.hamcrest.Matchers.notNullValue;
import static org.hamcrest.Matchers.nullValue;
import static org.hamcrest.Matchers.startsWith;
import static org.junit.jupiter.api.Assertions.assertFalse;

import io.github.rodrigofabreu.signalhub.TestClients;
import io.github.rodrigofabreu.signalhub.TestClients.Registered;
import io.github.rodrigofabreu.signalhub.TestProducers;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import io.restassured.response.ValidatableResponse;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/**
 * Managing one's own producers from a device, against real PostgreSQL: every role may, each
 * operation reaches only the caller's own producers, and a key is shown only where it is created.
 */
@QuarkusTest
class OwnProducerApiTest {

  private static final String PRODUCERS = "/api/v1/client/producers";
  private static final String EVENTS = "/api/v1/events";

  @ParameterizedTest
  @ValueSource(strings = {"BASIC", "MOD", "ADMIN"})
  void everyRoleRunsTheWholeLifecycleOfAnOwnProducer(String role) {
    var owner = TestClients.registerAs(role, "own-" + role);
    var name = "own-" + role.toLowerCase() + "-" + UUID.randomUUID();

    var created = create(owner, Map.of("name", name));
    created
        .statusCode(201)
        .header("Location", containsString(PRODUCERS + "/"))
        .body("producer.name", equalTo(name))
        .body("producer.visibility", equalTo("PRIVATE"))
        .body("producer.subscribed", equalTo(true))
        .body("producer.keys", hasSize(1))
        .body("producer.keys[0].id", equalTo(created.extract().path("keyId")))
        .body("producer.keys[0].prefix", startsWith("shpk1_"))
        .body("producer.keys[0].revokedAt", nullValue())
        .body("apiKey", startsWith("shpk1_"));
    var id = created.extract().<String>path("producer.id");
    var key = created.extract().<String>path("apiKey");
    var keyId = created.extract().<String>path("keyId");
    var prefix = created.extract().<String>path("producer.keys[0].prefix");
    org.junit.jupiter.api.Assertions.assertTrue(key.startsWith(prefix + "_"));

    // The key publishes right away, and the owner receives the event.
    var eventId = publish(key, "first");
    asClient(owner.clientKey()).get(EVENTS + "/" + eventId).then().statusCode(200);

    // Listing and getting show the key by prefix only, never the key.
    var list = asClient(owner.clientKey()).get(PRODUCERS).then().statusCode(200);
    list.body("items.id", org.hamcrest.Matchers.hasItem(id))
        .body("items.find { it.id == '" + id + "' }.keys[0].prefix", equalTo(prefix))
        .body("items.find { it.id == '" + id + "' }.lastEventAt", notNullValue());
    assertFalse(list.extract().asString().contains(key), "the list shows a key");
    var got = asClient(owner.clientKey()).get(PRODUCERS + "/" + id).then().statusCode(200);
    got.body("id", equalTo(id)).body("keys[0]", not(hasKey("apiKey")));
    assertFalse(got.extract().asString().contains(key), "the producer shows a key");

    // A second key, then rotate: the first is revoked and stops publishing at once.
    var second = post(owner, PRODUCERS + "/" + id + "/keys").statusCode(201);
    var secondKey = second.extract().<String>path("apiKey");
    second.body("producer.keys", hasSize(2)).body("keyId", notNullValue());
    asProducer(secondKey)
        .contentType(ContentType.JSON)
        .body(Map.of("category", "INFO", "severity", "LOW", "title", "second"))
        .post(EVENTS)
        .then()
        .statusCode(201);
    post(owner, PRODUCERS + "/" + id + "/keys/" + keyId + "/revoke")
        .statusCode(200)
        .body("keys.find { it.id == '" + keyId + "' }.revokedAt", notNullValue());
    post(owner, PRODUCERS + "/" + id + "/keys/" + keyId + "/revoke").statusCode(200);
    publishAttempt(key).statusCode(401);
    publishAttempt(secondKey).statusCode(201);
    post(owner, PRODUCERS + "/" + id + "/keys/" + UUID.randomUUID() + "/revoke").statusCode(404);

    // Disabling stops every key; enabling brings back the keys that are not revoked.
    post(owner, PRODUCERS + "/" + id + "/disable")
        .statusCode(200)
        .body("disabledAt", notNullValue())
        .body("disabledByOperator", equalTo(false));
    publishAttempt(secondKey).statusCode(401);
    post(owner, PRODUCERS + "/" + id + "/disable").statusCode(200);
    post(owner, PRODUCERS + "/" + id + "/enable").statusCode(200).body("disabledAt", nullValue());
    publishAttempt(secondKey).statusCode(201);
    post(owner, PRODUCERS + "/" + id + "/enable").statusCode(200);

    // Renaming keeps keys and events.
    var renamed = name + "-renamed";
    patch(owner, PRODUCERS + "/" + id, Map.of("name", renamed))
        .statusCode(200)
        .body("name", equalTo(renamed));
    publishAttempt(secondKey).statusCode(201);
    asClient(owner.clientKey())
        .get(EVENTS + "/" + eventId)
        .then()
        .statusCode(200)
        .body("producer.name", equalTo(renamed));

    // Visibility.
    patch(owner, PRODUCERS + "/" + id, Map.of("visibility", "PUBLIC"))
        .statusCode(200)
        .body("visibility", equalTo("PUBLIC"));
  }

  @Test
  void aCreatedProducerCanBePublicFromTheStart() {
    var owner = TestClients.registerAs("BASIC", "own-public");
    create(owner, Map.of("name", unique("pub"), "visibility", "PUBLIC"))
        .statusCode(201)
        .body("producer.visibility", equalTo("PUBLIC"));
  }

  @Test
  void aProducerNameIsUniqueAcrossUsersAndTheConflictChangesNothing() {
    var anna = TestClients.registerAs("BASIC", "own-anna");
    var ben = TestClients.registerAs("MOD", "own-ben");
    var annas = unique("taken");
    create(anna, Map.of("name", annas)).statusCode(201);
    create(ben, Map.of("name", annas)).statusCode(409).body("violations[0].field", equalTo("name"));
    var bens = create(ben, Map.of("name", unique("bens"))).statusCode(201);
    var bensId = bens.extract().<String>path("producer.id");
    patch(ben, PRODUCERS + "/" + bensId, Map.of("name", annas)).statusCode(409);
    asClient(ben.clientKey())
        .get(PRODUCERS + "/" + bensId)
        .then()
        .statusCode(200)
        .body("name", not(equalTo(annas)));
    // Renaming to its own name is fine.
    var current = bens.extract().<String>path("producer.name");
    patch(ben, PRODUCERS + "/" + bensId, Map.of("name", current)).statusCode(200);
  }

  @Test
  void invalidBodiesAreRejected() {
    var owner = TestClients.registerAs("MOD", "own-invalid");
    create(owner, Map.of()).statusCode(400);
    create(owner, Map.of("name", "has space")).statusCode(400);
    create(owner, Map.of("name", unique("x"), "ownerId", UUID.randomUUID().toString()))
        .statusCode(400);
    create(owner, Map.of("name", unique("x"), "visibility", "SECRET")).statusCode(400);
    var id = create(owner, Map.of("name", unique("inv"))).extract().<String>path("producer.id");
    patch(owner, PRODUCERS + "/" + id, Map.of()).statusCode(400);
    patch(owner, PRODUCERS + "/" + id, Map.of("name", "")).statusCode(400);
    patch(owner, PRODUCERS + "/" + id, Map.of("name", "bad name")).statusCode(400);
    patch(owner, PRODUCERS + "/" + id, Map.of("allowedUserIds", java.util.List.of()))
        .statusCode(400);
  }

  @ParameterizedTest
  @ValueSource(strings = {"BASIC", "MOD", "ADMIN"})
  void nobodyReachesAnotherUsersProducerNotEvenAnAdmin(String role) {
    var mine = TestClients.registerAs(role, "own-intruder-" + role);
    var victim = TestClients.registerAs("BASIC", "own-victim");
    var created = create(victim, Map.of("name", unique("victims")));
    var id = created.extract().<String>path("producer.id");
    var keyId = created.extract().<String>path("keyId");
    var key = created.extract().<String>path("apiKey");
    var other = UUID.randomUUID();

    for (var path : new String[] {id, other.toString()}) {
      var url = PRODUCERS + "/" + path;
      asClient(mine.clientKey()).get(url).then().statusCode(404);
      patch(mine, url, Map.of("visibility", "PUBLIC")).statusCode(404);
      patch(mine, url, Map.of("name", unique("stolen"))).statusCode(404);
      post(mine, url + "/keys").statusCode(404);
      post(mine, url + "/keys/" + keyId + "/revoke").statusCode(404);
      post(mine, url + "/disable").statusCode(404);
      post(mine, url + "/enable").statusCode(404);
      asClient(mine.clientKey())
          .put(url + "/allowed-users/" + mine.userId())
          .then()
          .statusCode(404);
      asClient(mine.clientKey())
          .delete(url + "/allowed-users/" + victim.userId())
          .then()
          .statusCode(404);
    }
    // The same answer for a private producer of someone else's and for one that does not exist.
    asClient(mine.clientKey())
        .get(PRODUCERS)
        .then()
        .statusCode(200)
        .body("items.id", not(org.hamcrest.Matchers.hasItem(id)));

    // Nothing changed: the victim's producer is as it was and its key still publishes.
    asClient(victim.clientKey())
        .get(PRODUCERS + "/" + id)
        .then()
        .statusCode(200)
        .body("visibility", equalTo("PRIVATE"))
        .body("disabledAt", nullValue())
        .body("keys", hasSize(1))
        .body("keys[0].revokedAt", nullValue())
        .body("allowedUsers", empty());
    publishAttempt(key).statusCode(201);
  }

  @Test
  void aProducerOfTheOperatorsIsNotTheCallersEither() {
    var admin = TestClients.registerAs("ADMIN", "own-admin");
    var operators = TestProducers.register("own-operators");
    asClient(admin.clientKey()).get(PRODUCERS + "/" + operators.id()).then().statusCode(404);
    post(admin, PRODUCERS + "/" + operators.id() + "/keys").statusCode(404);
    asClient(admin.clientKey())
        .get(PRODUCERS)
        .then()
        .body("items.id", not(org.hamcrest.Matchers.hasItem(operators.id().toString())));
  }

  @Test
  void aProducerTheOperatorDisabledStaysDisabledForItsOwner() {
    var owner = TestClients.registerAs("MOD", "own-operator-disable");
    var created = create(owner, Map.of("name", unique("op")));
    var id = created.extract().<String>path("producer.id");
    var key = created.extract().<String>path("apiKey");

    asAdmin().post("/api/v1/admin/producers/" + id + "/disable").then().statusCode(200);
    get(owner, id).body("disabledAt", notNullValue()).body("disabledByOperator", equalTo(true));
    post(owner, PRODUCERS + "/" + id + "/enable").statusCode(409);
    // Disabling it again does not hand it to the owner.
    post(owner, PRODUCERS + "/" + id + "/disable").statusCode(200);
    post(owner, PRODUCERS + "/" + id + "/enable").statusCode(409);
    publishAttempt(key).statusCode(401);

    // The operator enables it; the owner disables and enables it as their own choice.
    asAdmin().post("/api/v1/admin/producers/" + id + "/enable").then().statusCode(200);
    publishAttempt(key).statusCode(201);
    post(owner, PRODUCERS + "/" + id + "/disable").statusCode(200);
    // The operator disabling what the owner disabled takes the choice away from the owner.
    asAdmin().post("/api/v1/admin/producers/" + id + "/disable").then().statusCode(200);
    post(owner, PRODUCERS + "/" + id + "/enable").statusCode(409);
  }

  @Test
  void aRevokedUserKeepsNoAccessAndTheirProducersAreDisabledForGood() {
    var owner = TestClients.registerAs("MOD", "own-revoked");
    var created = create(owner, Map.of("name", unique("rev")));
    var key = created.extract().<String>path("apiKey");
    asAdmin().post("/api/v1/admin/users/" + owner.userId() + "/revoke").then().statusCode(200);
    asClient(owner.clientKey()).get(PRODUCERS).then().statusCode(401);
    create(owner, Map.of("name", unique("late"))).statusCode(401);
    publishAttempt(key).statusCode(401);
  }

  @Test
  void aRevokedDeviceAndAMissingOrWrongKeyAreUnauthorizedOnEveryEndpoint() {
    var owner = TestClients.registerAs("MOD", "own-unauthorized");
    var id = create(owner, Map.of("name", unique("u"))).extract().<String>path("producer.id");
    asAdmin().post("/api/v1/admin/clients/" + owner.id() + "/revoke").then().statusCode(200);
    for (var request : requests(id)) {
      request.apply(asClient(owner.clientKey())).then().statusCode(401);
      request.apply(given()).then().statusCode(401);
      // The operator's token is not a client key.
      request
          .apply(given().header("Authorization", "Bearer " + adminToken()))
          .then()
          .statusCode(401);
      request
          .apply(given().header("Authorization", "Bearer shck1_nonsense"))
          .then()
          .statusCode(401);
    }
  }

  @Test
  void aProducerKeyIsNotAClientKey() {
    var owner = TestClients.registerAs("MOD", "own-keykind");
    var created = create(owner, Map.of("name", unique("kind")));
    var key = created.extract().<String>path("apiKey");
    asClient(key).get(PRODUCERS).then().statusCode(401);
  }

  @Test
  void logsCarryIdsOnlyNeverAKeyOrAPairingCode() {
    var records = new java.util.concurrent.CopyOnWriteArrayList<String>();
    var handler =
        new java.util.logging.Handler() {
          @Override
          public void publish(java.util.logging.LogRecord record) {
            var text = new java.util.logging.SimpleFormatter().formatMessage(record);
            records.add(text);
            if (record.getThrown() != null) {
              records.add(String.valueOf(record.getThrown()));
            }
          }

          @Override
          public void flush() {}

          @Override
          public void close() {}
        };
    var root = java.util.logging.Logger.getLogger("");
    root.addHandler(handler);
    try {
      var admin = TestClients.registerAs("ADMIN", "log-admin");
      var created = create(admin, Map.of("name", unique("logged"))).statusCode(201);
      var id = created.extract().<String>path("producer.id");
      var secrets = new java.util.ArrayList<String>();
      secrets.add(created.extract().path("apiKey"));
      secrets.add(post(admin, PRODUCERS + "/" + id + "/keys").extract().path("apiKey"));
      secrets.add(
          asClient(admin.clientKey())
              .contentType(ContentType.JSON)
              .body(Map.of("name", "logged-" + UUID.randomUUID()))
              .post("/api/v1/client/users")
              .then()
              .statusCode(201)
              .extract()
              .path("pairing.code"));
      post(admin, PRODUCERS + "/" + id + "/disable").statusCode(200);
      post(admin, PRODUCERS + "/" + id + "/enable").statusCode(200);
      patch(admin, PRODUCERS + "/" + id, Map.of("visibility", "PUBLIC")).statusCode(200);

      org.junit.jupiter.api.Assertions.assertFalse(records.isEmpty());
      for (var secret : secrets) {
        var tail = secret.substring(secret.lastIndexOf('_') + 1);
        for (var line : records) {
          assertFalse(line.contains(secret), "a log line holds a secret");
          assertFalse(line.contains(tail), "a log line holds a secret's random part");
        }
      }
    } finally {
      root.removeHandler(handler);
    }
  }

  // ---- helpers

  private interface Request {
    io.restassured.response.Response apply(io.restassured.specification.RequestSpecification spec);
  }

  private static Request[] requests(String id) {
    var some = UUID.randomUUID();
    return new Request[] {
      spec -> spec.contentType(ContentType.JSON).body(Map.of("name", "x")).post(PRODUCERS),
      spec -> spec.get(PRODUCERS),
      spec -> spec.get(PRODUCERS + "/" + id),
      spec ->
          spec.contentType(ContentType.JSON).body(Map.of("name", "y")).patch(PRODUCERS + "/" + id),
      spec -> spec.post(PRODUCERS + "/" + id + "/keys"),
      spec -> spec.post(PRODUCERS + "/" + id + "/keys/" + some + "/revoke"),
      spec -> spec.post(PRODUCERS + "/" + id + "/disable"),
      spec -> spec.post(PRODUCERS + "/" + id + "/enable"),
      spec -> spec.put(PRODUCERS + "/" + id + "/allowed-users/" + some),
      spec -> spec.delete(PRODUCERS + "/" + id + "/allowed-users/" + some),
    };
  }

  static String unique(String prefix) {
    return prefix + "-" + UUID.randomUUID();
  }

  static ValidatableResponse create(Registered caller, Map<String, ?> body) {
    return asClient(caller.clientKey())
        .contentType(ContentType.JSON)
        .body(body)
        .post(PRODUCERS)
        .then();
  }

  static ValidatableResponse post(Registered caller, String path) {
    return asClient(caller.clientKey()).post(path).then();
  }

  static ValidatableResponse patch(Registered caller, String path, Map<String, ?> body) {
    return asClient(caller.clientKey()).contentType(ContentType.JSON).body(body).patch(path).then();
  }

  private static ValidatableResponse get(Registered caller, String id) {
    return asClient(caller.clientKey()).get(PRODUCERS + "/" + id).then().statusCode(200);
  }

  static ValidatableResponse publishAttempt(String apiKey) {
    return asProducer(apiKey)
        .contentType(ContentType.JSON)
        .body(Map.of("category", "INFO", "severity", "LOW", "title", "t"))
        .post(EVENTS)
        .then();
  }

  static String publish(String apiKey, String title) {
    return asProducer(apiKey)
        .contentType(ContentType.JSON)
        .body(Map.of("category", "INFO", "severity", "LOW", "title", title))
        .post(EVENTS)
        .then()
        .statusCode(201)
        .extract()
        .path("id");
  }
}
