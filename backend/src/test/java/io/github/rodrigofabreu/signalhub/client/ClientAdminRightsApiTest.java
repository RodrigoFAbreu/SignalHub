package io.github.rodrigofabreu.signalhub.client;

import static io.github.rodrigofabreu.signalhub.TestClients.ADMIN;
import static io.github.rodrigofabreu.signalhub.TestClients.CLIENT;
import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.notNullValue;

import io.github.rodrigofabreu.signalhub.TestClients;
import io.github.rodrigofabreu.signalhub.push.FakePushProvider;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import io.restassured.response.ValidatableResponse;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/** Admin devices and renaming clients through the management API, against real PostgreSQL. */
@QuarkusTest
class ClientAdminRightsApiTest {

  @Test
  void aClientIsNotAnAdminUnlessRegisteredAsOne() {
    register("{\"name\": \"Plain\"}").body("client.admin", equalTo(false));
    register("{\"name\": \"Null\", \"admin\": null}").body("client.admin", equalTo(false));
    register("{\"name\": \"Not admin\", \"admin\": false}").body("client.admin", equalTo(false));
    register("{\"name\": \"Admin\", \"admin\": true}").body("client.admin", equalTo(true));
  }

  @Test
  void theFlagIsOnEveryClientResponse() {
    var created = register("{\"name\": \"Everywhere\", \"admin\": true}").extract();
    String id = created.path("client.id");
    String key = created.path("clientKey");

    asAdmin().get(ADMIN).then().body("items.find { it.id == '" + id + "' }.admin", equalTo(true));
    asAdmin().get(ADMIN + "/" + id).then().statusCode(200).body("admin", equalTo(true));
    // A client reads from its own registration whether it is an admin.
    asClient(key).get(CLIENT).then().statusCode(200).body("admin", equalTo(true));
    asClient(key)
        .contentType(ContentType.JSON)
        .body(Map.of("provider", FakePushProvider.NAME, "token", "admin-" + UUID.randomUUID()))
        .put(CLIENT + "/push-target")
        .then()
        .statusCode(200)
        .body("admin", equalTo(true));
    asClient(key)
        .contentType(ContentType.JSON)
        .body("{}")
        .put(CLIENT + "/push-preferences")
        .then()
        .statusCode(200)
        .body("admin", equalTo(true));
    asClient(key).delete(CLIENT + "/push-target").then().body("admin", equalTo(true));
    asAdmin()
        .post(ADMIN + "/" + id + "/revoke")
        .then()
        .statusCode(200)
        .body("admin", equalTo(true));
  }

  @Test
  void renamingChangesOnlyTheName() {
    var client = TestClients.register("Old name");

    update(client.id(), "{\"name\": \"Anna's phone\"}")
        .statusCode(200)
        .body("id", equalTo(client.id().toString()))
        .body("name", equalTo("Anna's phone"))
        .body("admin", equalTo(false))
        .body("pushStatus", notNullValue());

    asAdmin().get(ADMIN + "/" + client.id()).then().body("name", equalTo("Anna's phone"));
    // The key keeps working, and the client sees its new name.
    asClient(client.clientKey()).get(CLIENT).then().body("name", equalTo("Anna's phone"));
  }

  @Test
  void adminRightsAreGrantedAndTakenAway() {
    var client = TestClients.register("Promoted");

    update(client.id(), "{\"admin\": true}")
        .statusCode(200)
        .body("admin", equalTo(true))
        .body("name", equalTo("Promoted"));
    asClient(client.clientKey()).get(CLIENT).then().body("admin", equalTo(true));
    // Granting again changes nothing.
    update(client.id(), "{\"admin\": true}").statusCode(200).body("admin", equalTo(true));

    update(client.id(), "{\"admin\": false}").statusCode(200).body("admin", equalTo(false));
    asClient(client.clientKey()).get(CLIENT).then().body("admin", equalTo(false));
  }

  @Test
  void nameAndAdminChangeTogether() {
    var client = TestClients.register("Both");

    update(client.id(), "{\"name\": \"Both, renamed\", \"admin\": true}")
        .statusCode(200)
        .body("name", equalTo("Both, renamed"))
        .body("admin", equalTo(true));
  }

  @Test
  void aRevokedClientDoesNotChange() {
    var client = TestClients.register("Gone");
    asAdmin().post(ADMIN + "/" + client.id() + "/revoke").then().statusCode(200);

    update(client.id(), "{\"name\": \"Back\", \"admin\": true}")
        .statusCode(409)
        .body("title", equalTo("Client is revoked"))
        .body("status", equalTo(409));
    update(client.id(), "{\"admin\": true}").statusCode(409);

    asAdmin()
        .get(ADMIN + "/" + client.id())
        .then()
        .body("name", equalTo("Gone"))
        .body("admin", equalTo(false));
  }

  @Test
  void anUnknownClientIsNotFound() {
    update(UUID.randomUUID(), "{\"admin\": true}").statusCode(404);
  }

  @ParameterizedTest
  @ValueSource(
      strings = {
        "{}",
        "{\"name\": null, \"admin\": null}",
        "{\"name\": \"\"}",
        "{\"name\": \" \\t\"}",
        "{\"name\": \"a\\u0000b\"}",
        "{\"admin\": \"true\"}",
        "{\"admin\": 1}",
        "{\"name\": 5}",
        "{\"x\": 1}",
        "not json"
      })
  void invalidChangesAreRejected(String body) {
    var client = TestClients.register("Unchanged");

    update(client.id(), body).statusCode(400).body("title", equalTo("Invalid request"));

    asAdmin()
        .get(ADMIN + "/" + client.id())
        .then()
        .body("name", equalTo("Unchanged"))
        .body("admin", equalTo(false));
  }

  @Test
  void aNameLongerThan100CharactersIsRejected() {
    var client = TestClients.register("Short");
    update(client.id(), "{\"name\": \"" + "x".repeat(101) + "\"}")
        .statusCode(400)
        .body("violations[0].field", equalTo("name"));
  }

  @Test
  void anInvalidAdminFlagIsRejectedWhenRegistering() {
    asAdmin()
        .contentType(ContentType.JSON)
        .body("{\"name\": \"x\", \"admin\": \"yes\"}")
        .post(ADMIN)
        .then()
        .statusCode(400)
        .body("violations[0].field", equalTo("admin"));
  }

  @Test
  void changingAClientNeedsTheAdminToken() {
    var client = TestClients.register("Protected");
    var other = TestClients.register("Other");
    var path = ADMIN + "/" + client.id();

    given()
        .contentType(ContentType.JSON)
        .body("{\"admin\": true}")
        .patch(path)
        .then()
        .statusCode(401);
    // Not even a client can make itself an admin.
    asClient(client.clientKey())
        .contentType(ContentType.JSON)
        .body("{\"admin\": true}")
        .patch(path)
        .then()
        .statusCode(401);
    asClient(other.clientKey())
        .contentType(ContentType.JSON)
        .body("{\"admin\": true}")
        .patch(path)
        .then()
        .statusCode(401);
    asAdmin().get(path).then().body("admin", equalTo(false));
  }

  private static ValidatableResponse register(String body) {
    return asAdmin().contentType(ContentType.JSON).body(body).post(ADMIN).then().statusCode(201);
  }

  private static ValidatableResponse update(UUID id, String body) {
    return asAdmin().contentType(ContentType.JSON).body(body).patch(ADMIN + "/" + id).then();
  }
}
