package io.github.rodrigofabreu.signalhub.client;

import static io.github.rodrigofabreu.signalhub.TestClients.ADMIN;
import static io.github.rodrigofabreu.signalhub.TestClients.CLIENT;
import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.not;

import io.github.rodrigofabreu.signalhub.TestClients;
import io.github.rodrigofabreu.signalhub.TestClients.Registered;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import io.restassured.response.ValidatableResponse;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/** Renaming devices from a device, as the user's role allows, against real PostgreSQL. */
@QuarkusTest
class DeviceRenameApiTest {

  private static final String DEVICES = CLIENT + "/devices";

  @Test
  void aBasicUserRenamesNoDeviceNotEvenTheirOwn() {
    var caller = TestClients.registerAs("BASIC", "rename-basic");
    var other = TestClients.registerAs("MOD", "rename-basic-other");
    for (var id : new UUID[] {caller.id(), other.id(), UUID.randomUUID()}) {
      rename(caller, id, "stolen").statusCode(403);
    }
    nameOf(caller.id(), "rename-basic");
    nameOf(other.id(), "rename-basic-other");
  }

  @Test
  void aModRenamesTheirOwnDevicesOnly() {
    var caller = TestClients.registerAs("MOD", "rename-mod");
    var second = TestClients.registerFor(caller.userId(), "rename-mod-second");
    var stranger = TestClients.registerAs("BASIC", "rename-mod-stranger");
    var admins = TestClients.register("rename-mod-admins");

    rename(caller, second.id(), "Anna's phone")
        .statusCode(200)
        .body("id", equalTo(second.id().toString()))
        .body("name", equalTo("Anna's phone"))
        .body("pushStatus.pendingRetries", equalTo(0));
    // Renaming the calling device itself works too, and its key keeps working.
    rename(caller, caller.id(), "this one").statusCode(200).body("name", equalTo("this one"));
    asClient(caller.clientKey())
        .get(CLIENT)
        .then()
        .statusCode(200)
        .body("name", equalTo("this one"));
    // Naming it as it is changes nothing.
    rename(caller, caller.id(), "this one").statusCode(200);

    // Other users' devices, an admin's, and unknown ones are all "not found" to a mod.
    for (var id : new UUID[] {stranger.id(), admins.id(), UUID.randomUUID()}) {
      rename(caller, id, "stolen").statusCode(404);
    }
    nameOf(stranger.id(), "rename-mod-stranger");
    nameOf(admins.id(), "rename-mod-admins");
  }

  @Test
  void anAdminRenamesDevicesOfUsersWhoAreNotAdminsOnly() {
    var caller = TestClients.registerAs("ADMIN", "rename-admin");
    var mods = TestClients.registerAs("MOD", "rename-admin-mod");
    var basics = TestClients.registerAs("BASIC", "rename-admin-basic");
    var otherAdmin = TestClients.registerAs("ADMIN", "rename-admin-other");

    rename(caller, mods.id(), "mod's").statusCode(200).body("name", equalTo("mod's"));
    rename(caller, basics.id(), "basic's").statusCode(200).body("name", equalTo("basic's"));
    rename(caller, otherAdmin.id(), "stolen").statusCode(409);
    rename(caller, caller.id(), "stolen").statusCode(409);
    rename(caller, UUID.randomUUID(), "stolen").statusCode(404);
    nameOf(otherAdmin.id(), "rename-admin-other");
    nameOf(caller.id(), "rename-admin");
  }

  @Test
  void aRevokedDeviceIsNotRenamed() {
    var caller = TestClients.registerAs("MOD", "rename-revoked-owner");
    var second = TestClients.registerFor(caller.userId(), "rename-revoked");
    asAdmin().post(ADMIN + "/" + second.id() + "/revoke").then().statusCode(200);

    rename(caller, second.id(), "late").statusCode(409);
    nameOf(second.id(), "rename-revoked");
  }

  @ParameterizedTest
  @ValueSource(strings = {"BASIC", "MOD", "ADMIN"})
  void aRevokedCallerIsUnauthorized(String role) {
    var caller = TestClients.registerAs(role, "rename-gone-" + role);
    asAdmin().post(ADMIN + "/" + caller.id() + "/revoke").then().statusCode(200);

    rename(caller, caller.id(), "x").statusCode(401);
    given()
        .contentType(ContentType.JSON)
        .body(Map.of("name", "x"))
        .patch(DEVICES + "/" + caller.id())
        .then()
        .statusCode(401);
  }

  @Test
  void theNameIsValidatedAsWhenPairing() {
    var caller = TestClients.registerAs("MOD", "rename-invalid");
    rename(caller, caller.id(), "").statusCode(400);
    rename(caller, caller.id(), "   ").statusCode(400);
    rename(caller, caller.id(), "x".repeat(101)).statusCode(400);
    rename(caller, caller.id(), "has\u0000nul").statusCode(400);
    asClient(caller.clientKey())
        .contentType(ContentType.JSON)
        .body(Map.of())
        .patch(DEVICES + "/" + caller.id())
        .then()
        .statusCode(400);
    asClient(caller.clientKey())
        .contentType(ContentType.JSON)
        .body(Map.of("name", "ok", "admin", true))
        .patch(DEVICES + "/" + caller.id())
        .then()
        .statusCode(400);
    nameOf(caller.id(), "rename-invalid");
    asAdmin().get(ADMIN + "/" + caller.id()).then().body("name", not(equalTo("ok")));
  }

  private static ValidatableResponse rename(Registered caller, UUID id, String name) {
    return asClient(caller.clientKey())
        .contentType(ContentType.JSON)
        .body(Map.of("name", name))
        .patch(DEVICES + "/" + id)
        .then();
  }

  private static void nameOf(UUID id, String name) {
    asAdmin().get(ADMIN + "/" + id).then().statusCode(200).body("name", equalTo(name));
  }
}
