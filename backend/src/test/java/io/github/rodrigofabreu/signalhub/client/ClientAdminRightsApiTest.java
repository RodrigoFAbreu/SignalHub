package io.github.rodrigofabreu.signalhub.client;

import static io.github.rodrigofabreu.signalhub.TestClients.ADMIN;
import static io.github.rodrigofabreu.signalhub.TestClients.CLIENT;
import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.notNullValue;

import io.github.rodrigofabreu.signalhub.TestClients;
import io.github.rodrigofabreu.signalhub.TestUsers;
import io.github.rodrigofabreu.signalhub.push.FakePushProvider;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import io.restassured.response.ValidatableResponse;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/**
 * Which devices are admin devices, and renaming clients, through the management API, against real
 * PostgreSQL.
 */
@QuarkusTest
class ClientAdminRightsApiTest {

  @Test
  void aClientIsAnAdminDeviceExactlyWhenItsUserIsAnAdmin() {
    for (var role : new String[] {"BASIC", "MOD"}) {
      var user = TestUsers.create("rights-" + role, role);
      registerFor(user.id(), "Device")
          .body("client.admin", equalTo(false))
          .body("client.user.id", equalTo(user.id().toString()))
          .body("client.user.role", equalTo(role));
    }
    var admin = TestUsers.create("rights-admin", "ADMIN");
    registerFor(admin.id(), "Device")
        .body("client.admin", equalTo(true))
        .body("client.user.role", equalTo("ADMIN"));
    // With no user named, the owner of the instance, an admin from the migration.
    register("{\"name\": \"Plain\"}").body("client.admin", equalTo(true));
  }

  @Test
  void theAdminFlagOfARegistrationCannotBeChosen() {
    var user = TestUsers.create("rights-flag", "MOD");
    // The flag a client could be registered with is kept only so that old requests still work.
    registerFor(user.id(), "Null", "null").body("client.admin", equalTo(false));
    registerFor(user.id(), "False", "false").body("client.admin", equalTo(false));
    asAdmin()
        .contentType(ContentType.JSON)
        .body(Map.of("name", "Admin", "userId", user.id().toString(), "admin", true))
        .post(ADMIN)
        .then()
        .statusCode(409)
        .body("title", equalTo("Roles are set per user, not per device"));
    var admin = TestUsers.create("rights-flag-admin", "ADMIN");
    registerFor(admin.id(), "Admin", "true").body("client.admin", equalTo(true));
  }

  @Test
  void theFlagAndTheUserAreOnEveryClientResponse() {
    var user = TestUsers.create("rights-everywhere", "ADMIN");
    var created = registerFor(user.id(), "Everywhere").extract();
    String id = created.path("client.id");
    String key = created.path("clientKey");

    asAdmin().get(ADMIN).then().body("items.find { it.id == '" + id + "' }.admin", equalTo(true));
    asAdmin()
        .get(ADMIN + "/" + id)
        .then()
        .statusCode(200)
        .body("admin", equalTo(true))
        .body("user.name", equalTo(user.name()));
    // A client reads from its own registration whether it is an admin, and whose it is.
    asClient(key)
        .get(CLIENT)
        .then()
        .statusCode(200)
        .body("admin", equalTo(true))
        .body("user.id", equalTo(user.id().toString()))
        .body("user.role", equalTo("ADMIN"));
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
    var client = TestClients.registerAs("MOD", "Old name");

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
  void aClientsAdminFlagCannotBeChanged() {
    var client = TestClients.registerAs("MOD", "Not promotable");
    var admin = TestClients.registerAs("ADMIN", "Not demotable");

    update(client.id(), "{\"admin\": true}")
        .statusCode(409)
        .body("title", equalTo("Roles are set per user, not per device"));
    update(admin.id(), "{\"admin\": false}")
        .statusCode(409)
        .body("title", equalTo("Roles are set per user, not per device"));
    asClient(client.clientKey()).get(CLIENT).then().body("admin", equalTo(false));
    asClient(admin.clientKey()).get(CLIENT).then().body("admin", equalTo(true));

    // What it already is changes nothing, and is allowed beside a new name.
    update(client.id(), "{\"name\": \"Same role\", \"admin\": false}")
        .statusCode(200)
        .body("name", equalTo("Same role"))
        .body("admin", equalTo(false));
    // A refused change leaves the name too.
    update(client.id(), "{\"name\": \"Never\", \"admin\": true}").statusCode(409);
    asAdmin().get(ADMIN + "/" + client.id()).then().body("name", equalTo("Same role"));
  }

  @Test
  void aRevokedClientDoesNotChange() {
    var client = TestClients.registerAs("MOD", "Gone");
    asAdmin().post(ADMIN + "/" + client.id() + "/revoke").then().statusCode(200);

    update(client.id(), "{\"name\": \"Back\"}")
        .statusCode(409)
        .body("title", equalTo("Client is revoked"))
        .body("status", equalTo(409));

    asAdmin().get(ADMIN + "/" + client.id()).then().body("name", equalTo("Gone"));
  }

  @Test
  void anUnknownClientIsNotFound() {
    update(UUID.randomUUID(), "{\"name\": \"x\"}").statusCode(404);
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
    var client = TestClients.registerAs("MOD", "Unchanged");

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
    var client = TestClients.registerAs("MOD", "Protected");
    var other = TestClients.registerAs("MOD", "Other");
    var path = ADMIN + "/" + client.id();

    given()
        .contentType(ContentType.JSON)
        .body("{\"name\": \"x\"}")
        .patch(path)
        .then()
        .statusCode(401);
    // Not even a client can change itself.
    asClient(client.clientKey())
        .contentType(ContentType.JSON)
        .body("{\"name\": \"x\"}")
        .patch(path)
        .then()
        .statusCode(401);
    asClient(other.clientKey())
        .contentType(ContentType.JSON)
        .body("{\"name\": \"x\"}")
        .patch(path)
        .then()
        .statusCode(401);
    asAdmin().get(path).then().body("name", equalTo("Protected"));
  }

  private static ValidatableResponse register(String body) {
    return asAdmin().contentType(ContentType.JSON).body(body).post(ADMIN).then().statusCode(201);
  }

  private static ValidatableResponse registerFor(UUID userId, String name) {
    return register("{\"name\": \"" + name + "\", \"userId\": \"" + userId + "\"}");
  }

  private static ValidatableResponse registerFor(UUID userId, String name, String admin) {
    return register(
        "{\"name\": \"" + name + "\", \"userId\": \"" + userId + "\", \"admin\": " + admin + "}");
  }

  private static ValidatableResponse update(UUID id, String body) {
    return asAdmin().contentType(ContentType.JSON).body(body).patch(ADMIN + "/" + id).then();
  }
}
