package io.github.rodrigofabreu.signalhub.user;

import static io.github.rodrigofabreu.signalhub.TestClients.CLIENT;
import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.contains;
import static org.hamcrest.Matchers.empty;
import static org.hamcrest.Matchers.endsWith;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.hasKey;
import static org.hamcrest.Matchers.not;
import static org.hamcrest.Matchers.notNullValue;
import static org.hamcrest.Matchers.nullValue;
import static org.junit.jupiter.api.Assertions.assertEquals;

import io.github.rodrigofabreu.signalhub.TestClients;
import io.github.rodrigofabreu.signalhub.TestProducers;
import io.github.rodrigofabreu.signalhub.TestUsers;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import io.restassured.response.ValidatableResponse;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/** The operator's user management API, against real PostgreSQL. */
@QuarkusTest
class UserAdminApiTest {

  private static final String USERS = TestUsers.ADMIN;

  @Test
  void theMigrationLeavesTheOwnerAsAnAdmin() {
    var owner = asAdmin().get(USERS).then().statusCode(200).extract().jsonPath();

    assertEquals("ADMIN", owner.getString("items[0].role"));
    assertEquals("Owner", owner.getString("items[0].name"));
  }

  @Test
  void aUserIsInvitedWithARoleAndNoDevice() {
    var name = "Anna " + UUID.randomUUID();

    var created =
        invite("{\"name\": \"" + name + "\", \"role\": \"MOD\"}")
            .statusCode(201)
            .header("Location", endsWith("/api/v1/admin/users/" + id(name)))
            .body("name", equalTo(name))
            .body("role", equalTo("MOD"))
            .body("revokedAt", nullValue())
            .body("devices", empty())
            .body("producers", empty())
            .body("subscriptions", empty())
            .extract();

    asAdmin()
        .get(USERS + "/" + created.<String>path("id"))
        .then()
        .statusCode(200)
        .body("name", equalTo(name));
    asAdmin().get(USERS).then().body("items.name", hasItem(name));
  }

  @Test
  void aUserIsBasicUnlessInvitedWithARole() {
    invite("{\"name\": \"Plain " + UUID.randomUUID() + "\"}").body("role", equalTo("BASIC"));
    invite("{\"name\": \"Null " + UUID.randomUUID() + "\", \"role\": null}")
        .body("role", equalTo("BASIC"));
    invite("{\"name\": \"Admin " + UUID.randomUUID() + "\", \"role\": \"ADMIN\"}")
        .body("role", equalTo("ADMIN"));
  }

  @Test
  void aNameIsUniqueIgnoringCase() {
    var name = "Unique " + UUID.randomUUID();
    invite("{\"name\": \"" + name + "\"}").statusCode(201);

    invite("{\"name\": \"" + name.toUpperCase() + "\"}")
        .statusCode(409)
        .body("title", equalTo("User name already exists"));
  }

  @ParameterizedTest
  @ValueSource(
      strings = {
        "{}",
        "{\"name\": \"\"}",
        "{\"name\": \"  \"}",
        "{\"name\": \"a\\u0000b\"}",
        "{\"name\": null}",
        "{\"name\": 5}",
        "{\"name\": \"x\", \"role\": \"OWNER\"}",
        "{\"name\": \"x\", \"role\": \"admin\"}",
        "{\"name\": \"x\", \"admin\": true}",
        "not json"
      })
  void invalidInvitationsAreRejected(String body) {
    invite(body).statusCode(400).body("title", equalTo("Invalid request"));
  }

  @Test
  void aNameLongerThan100CharactersIsRejected() {
    invite("{\"name\": \"" + "x".repeat(101) + "\"}")
        .statusCode(400)
        .body("violations[0].field", equalTo("name"));
  }

  @Test
  void theRoleAndTheNameChange() {
    var user = TestUsers.create("changing", "BASIC");
    var device = TestClients.registerFor(user.id(), "Phone");
    asClient(device.clientKey()).get(CLIENT).then().body("admin", equalTo(false));

    update(user.id(), "{\"role\": \"ADMIN\"}")
        .statusCode(200)
        .body("role", equalTo("ADMIN"))
        .body("name", equalTo(user.name()));
    // A device is an admin device exactly when its user is an admin: the role carries over.
    asClient(device.clientKey())
        .get(CLIENT)
        .then()
        .body("admin", equalTo(true))
        .body("user.role", equalTo("ADMIN"));

    var renamed = "Renamed " + UUID.randomUUID();
    update(user.id(), "{\"name\": \"" + renamed + "\", \"role\": \"MOD\"}")
        .statusCode(200)
        .body("name", equalTo(renamed))
        .body("role", equalTo("MOD"));
    asClient(device.clientKey())
        .get(CLIENT)
        .then()
        .body("admin", equalTo(false))
        .body("user.name", equalTo(renamed));
    asAdmin()
        .get("/api/v1/admin/clients/" + device.id())
        .then()
        .body("user.name", equalTo(renamed));
  }

  @Test
  void aRenameToAnotherUsersNameIsRefused() {
    var first = TestUsers.create("first", "BASIC");
    var second = TestUsers.create("second", "BASIC");

    update(second.id(), "{\"name\": \"" + first.name().toUpperCase() + "\"}")
        .statusCode(409)
        .body("title", equalTo("User name already exists"));
    // Its own name, whatever the case, is not another's.
    update(second.id(), "{\"name\": \"" + second.name().toUpperCase() + "\"}").statusCode(200);
    asAdmin().get(USERS + "/" + second.id()).then().body("role", equalTo("BASIC"));
  }

  @ParameterizedTest
  @ValueSource(
      strings = {
        "{}",
        "{\"name\": null, \"role\": null}",
        "{\"name\": \"\"}",
        "{\"name\": \" \\t\"}",
        "{\"name\": \"a\\u0000b\"}",
        "{\"role\": \"OWNER\"}",
        "{\"role\": 1}",
        "{\"x\": 1}",
        "not json"
      })
  void invalidChangesAreRejected(String body) {
    var user = TestUsers.create("unchanged", "MOD");

    update(user.id(), body).statusCode(400).body("title", equalTo("Invalid request"));

    asAdmin()
        .get(USERS + "/" + user.id())
        .then()
        .body("name", equalTo(user.name()))
        .body("role", equalTo("MOD"));
  }

  @Test
  void anUnknownUserIsNotFound() {
    var unknown = UUID.randomUUID();

    asAdmin().get(USERS + "/" + unknown).then().statusCode(404);
    update(unknown, "{\"role\": \"MOD\"}").statusCode(404);
    asAdmin().post(USERS + "/" + unknown + "/revoke").then().statusCode(404);
    asAdmin().get(USERS + "/not-a-uuid").then().statusCode(404);
  }

  @Test
  void revokingAUserRevokesTheirDevicesAndDisablesTheirProducers() {
    var user = TestUsers.create("revoked", "ADMIN");
    var phone = TestClients.registerFor(user.id(), "Phone");
    var tablet = TestClients.registerFor(user.id(), "Tablet");
    var producer = TestProducers.register("revoked-user", user.id(), "PUBLIC");
    var other = TestUsers.create("revoked-bystander", "BASIC");
    var bystander = TestClients.registerFor(other.id(), "Bystander");
    TestUsers.subscribe(other.id(), producer.id());

    var revoked =
        asAdmin()
            .post(USERS + "/" + user.id() + "/revoke")
            .then()
            .statusCode(200)
            .body("revokedAt", notNullValue())
            // A revoked user is never an admin.
            .body("role", equalTo("BASIC"))
            .body("devices.revokedAt", contains(notNullValue(), notNullValue()))
            .body("producers.disabledAt", contains(notNullValue()))
            .extract()
            .<String>path("revokedAt");

    asClient(phone.clientKey()).get(CLIENT).then().statusCode(401);
    asClient(tablet.clientKey()).get(CLIENT).then().statusCode(401);
    asAdmin()
        .get(TestProducers.ADMIN + "/" + producer.id())
        .then()
        .body("disabledAt", notNullValue());
    // Others are not touched.
    asClient(bystander.clientKey()).get(CLIENT).then().statusCode(200);
    // Revoking again changes nothing.
    asAdmin()
        .post(USERS + "/" + user.id() + "/revoke")
        .then()
        .statusCode(200)
        .body("revokedAt", equalTo(revoked));
  }

  @Test
  void aRevokedUserNeitherChangesNorGetsNewDevices() {
    var user = TestUsers.create("gone", "MOD");
    asAdmin().post(USERS + "/" + user.id() + "/revoke").then().statusCode(200);

    update(user.id(), "{\"role\": \"ADMIN\"}")
        .statusCode(409)
        .body("title", equalTo("User is revoked"));
    update(user.id(), "{\"name\": \"Back\"}").statusCode(409);
    asAdmin()
        .contentType(ContentType.JSON)
        .body(Map.of("name", "Phone", "userId", user.id().toString()))
        .post("/api/v1/admin/clients")
        .then()
        .statusCode(409);
    asAdmin()
        .contentType(ContentType.JSON)
        .body(Map.of("name", "Late", "ownerId", user.id().toString()))
        .post(TestProducers.ADMIN)
        .then()
        .statusCode(409);
    asAdmin().get(USERS + "/" + user.id()).then().body("role", equalTo("BASIC"));
  }

  @Test
  void aUserCannotBeSubscribedToAProducerTheyDoNotSee() {
    var user = TestUsers.create("blind", "BASIC");
    var hidden = TestProducers.register("blind-private");
    var seen = TestProducers.registerPublic("blind-public");

    asAdmin()
        .put(USERS + "/" + user.id() + "/subscriptions/" + hidden.id())
        .then()
        .statusCode(409)
        .body("title", equalTo("The user does not see this producer"));
    asAdmin()
        .put(USERS + "/" + user.id() + "/subscriptions/" + seen.id())
        .then()
        .statusCode(200)
        .body("subscriptions.id", contains(seen.id().toString()));
    // Again changes nothing.
    asAdmin()
        .put(USERS + "/" + user.id() + "/subscriptions/" + seen.id())
        .then()
        .statusCode(200)
        .body("subscriptions.size()", equalTo(1));
    asAdmin()
        .put(USERS + "/" + user.id() + "/subscriptions/" + UUID.randomUUID())
        .then()
        .statusCode(404);
    asAdmin()
        .put(USERS + "/" + UUID.randomUUID() + "/subscriptions/" + seen.id())
        .then()
        .statusCode(404);
    asAdmin()
        .delete(USERS + "/" + user.id() + "/subscriptions/" + seen.id())
        .then()
        .statusCode(200)
        .body("subscriptions", empty());
    // Unsubscribing a user who is not subscribed changes nothing.
    asAdmin()
        .delete(USERS + "/" + user.id() + "/subscriptions/" + seen.id())
        .then()
        .statusCode(200);
  }

  @Test
  void aUserListsTheirDevicesProducersAndSubscriptionsWithoutKeys() {
    var user = TestUsers.create("listed", "MOD");
    var device = TestClients.registerFor(user.id(), "Listed phone");
    var producer = TestProducers.register("listed", user.id(), "PRIVATE");

    var listed = asAdmin().get(USERS + "/" + user.id()).then().statusCode(200);

    listed
        .body("devices.name", contains("Listed phone"))
        .body("devices.id", contains(device.id().toString()))
        .body("devices[0]", not(hasKey("clientKey")))
        .body("producers.name", contains(producer.name()))
        .body("producers[0].visibility", equalTo("PRIVATE"))
        // A producer's owner is subscribed when it is created.
        .body("subscriptions.id", contains(producer.id().toString()))
        .body("producers[0]", not(hasKey("apiKey")));
  }

  @Test
  void theEndpointsNeedTheAdminToken() {
    var user = TestUsers.create("protected", "BASIC");
    var device = TestClients.registerFor(user.id(), "Protected phone");

    given().get(USERS).then().statusCode(401);
    given()
        .contentType(ContentType.JSON)
        .body("{\"name\": \"x\"}")
        .post(USERS)
        .then()
        .statusCode(401);
    // Not even a device of an admin user can: roles are set only with the admin token.
    var admin = TestClients.registerAs("ADMIN", "admin-device");
    for (var key : List.of(device.clientKey(), admin.clientKey())) {
      asClient(key).get(USERS).then().statusCode(401);
      asClient(key)
          .contentType(ContentType.JSON)
          .body("{\"role\": \"ADMIN\"}")
          .patch(USERS + "/" + user.id())
          .then()
          .statusCode(401);
      asClient(key).post(USERS + "/" + user.id() + "/revoke").then().statusCode(401);
      asClient(key)
          .put(USERS + "/" + user.id() + "/subscriptions/" + UUID.randomUUID())
          .then()
          .statusCode(401);
    }
    asAdmin().get(USERS + "/" + user.id()).then().body("role", equalTo("BASIC"));
  }

  private static ValidatableResponse invite(String body) {
    return asAdmin().contentType(ContentType.JSON).body(body).post(USERS).then();
  }

  private static ValidatableResponse update(UUID id, String body) {
    return asAdmin().contentType(ContentType.JSON).body(body).patch(USERS + "/" + id).then();
  }

  /** The ID of the user with this name. */
  private static String id(String name) {
    return asAdmin()
        .get(USERS)
        .then()
        .extract()
        .path("items.find { it.name == '" + name + "' }.id");
  }
}
