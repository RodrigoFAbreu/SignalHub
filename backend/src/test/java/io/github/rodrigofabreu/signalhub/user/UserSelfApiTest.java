package io.github.rodrigofabreu.signalhub.user;

import static io.github.rodrigofabreu.signalhub.TestClients.CLIENT;
import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.adminToken;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.contains;
import static org.hamcrest.Matchers.containsInAnyOrder;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.not;
import static org.hamcrest.Matchers.notNullValue;
import static org.hamcrest.Matchers.startsWith;

import io.github.rodrigofabreu.signalhub.TestClients;
import io.github.rodrigofabreu.signalhub.TestClients.Registered;
import io.github.rodrigofabreu.signalhub.TestProducers;
import io.github.rodrigofabreu.signalhub.TestUsers;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import io.restassured.response.ValidatableResponse;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/**
 * Users from a device, against real PostgreSQL: every role lists names, only an admin invites users
 * and sets BASIC or MOD, and nobody makes an admin.
 */
@QuarkusTest
class UserSelfApiTest {

  private static final String USERS = CLIENT + "/users";

  @ParameterizedTest
  @ValueSource(strings = {"BASIC", "MOD"})
  void aBasicOrModUserListsTheNamesOfTheUsersWhoAreNotRevokedAndNothingElse(String role) {
    var caller = TestClients.registerAs(role, "names-" + role);
    var active = TestUsers.create("names-active", "BASIC");
    var revoked = TestUsers.create("names-revoked", "MOD");
    asAdmin().post(TestUsers.ADMIN + "/" + revoked.id() + "/revoke").then().statusCode(200);

    asClient(caller.clientKey())
        .get(USERS)
        .then()
        .statusCode(200)
        .body("items.id", hasItem(active.id().toString()))
        .body("items.id", hasItem(caller.userId().toString()))
        .body("items.id", not(hasItem(revoked.id().toString())))
        // Every user is an ID and a name: no role, device count or producer, so admins are not
        // told apart.
        .body("items.collect { it.keySet() }.flatten().unique()", containsInAnyOrder("id", "name"));
  }

  @Test
  void anAdminListsEveryUsersRoleAndDevices() {
    var admin = TestClients.registerAs("ADMIN", "people-admin");
    var mod = TestClients.registerAs("MOD", "people-mod");
    TestClients.registerFor(mod.userId(), "people-mod-second");
    var noDevice = TestUsers.create("people-invited", "BASIC");
    var allRevoked = TestClients.registerAs("BASIC", "people-gone");
    asAdmin().post(TestClients.ADMIN + "/" + allRevoked.id() + "/revoke").then().statusCode(200);
    var revokedUser = TestUsers.create("people-revoked", "MOD");
    asAdmin().post(TestUsers.ADMIN + "/" + revokedUser.id() + "/revoke").then().statusCode(200);

    var list = asClient(admin.clientKey()).get(USERS).then().statusCode(200);
    list.body(
        "items.collect { it.keySet() }.flatten().unique()",
        containsInAnyOrder("id", "name", "role", "activeDevices", "hasPaired"));
    list.body("items.id", not(hasItem(revokedUser.id().toString())));
    person(list, admin.userId(), "ADMIN", 1, true);
    person(list, mod.userId(), "MOD", 2, true);
    // Invited, no device yet.
    person(list, noDevice.id(), "BASIC", 0, false);
    // Had a device, now revoked: still paired once, none active.
    person(list, allRevoked.userId(), "BASIC", 0, true);
  }

  @Test
  void anAdminReadsTheProducersAUserOwns() {
    var admin = TestClients.registerAs("ADMIN", "owned-admin");
    var owner = TestUsers.create("owned-owner", "BASIC");
    var other = TestUsers.create("owned-other", "BASIC");
    var pub = TestProducers.register("owned-b-pub", owner.id(), "PUBLIC");
    var priv = TestProducers.register("owned-a-priv", owner.id(), "PRIVATE");
    TestProducers.register("owned-not-theirs", other.id(), "PRIVATE");
    asAdmin().post(TestProducers.ADMIN + "/" + priv.id() + "/disable").then().statusCode(200);

    var response = asClient(admin.clientKey()).get(USERS + "/" + owner.id() + "/producers").then();
    response
        .statusCode(200)
        .body("items.size()", equalTo(2))
        .body("items.id", contains(priv.id().toString(), pub.id().toString()))
        .body("items[0].name", equalTo(priv.name()))
        .body("items[0].visibility", equalTo("PRIVATE"))
        .body("items[0].disabled", equalTo(true))
        .body("items[1].visibility", equalTo("PUBLIC"))
        .body("items[1].disabled", equalTo(false))
        // An ID, a name, a visibility and whether it is disabled: no key, no allow-list.
        .body(
            "items.collect { it.keySet() }.flatten().unique()",
            containsInAnyOrder("id", "name", "visibility", "disabled"));

    var none = TestUsers.create("owned-none", "MOD");
    asClient(admin.clientKey())
        .get(USERS + "/" + none.id() + "/producers")
        .then()
        .statusCode(200)
        .body("items.size()", equalTo(0));
  }

  @ParameterizedTest
  @ValueSource(strings = {"BASIC", "MOD"})
  void onlyAnAdminReadsPeoplesDetails(String role) {
    var caller = TestClients.registerAs(role, "details-" + role);
    var owner = TestUsers.create("details-owner", "BASIC");
    TestProducers.register("details-prod", owner.id(), "PUBLIC");

    // Forbidden for an existing user, an unknown one and oneself alike: nothing to tell apart.
    for (var id : new UUID[] {owner.id(), caller.userId(), UUID.randomUUID()}) {
      asClient(caller.clientKey()).get(USERS + "/" + id + "/producers").then().statusCode(403);
    }
    asClient(caller.clientKey())
        .get(USERS)
        .then()
        .statusCode(200)
        .body("items.collect { it.keySet() }.flatten().unique()", containsInAnyOrder("id", "name"));
  }

  @Test
  void aRevokedOrUnknownUserHasNoProducersToRead() {
    var admin = TestClients.registerAs("ADMIN", "owned-gone-admin");
    var revoked = TestUsers.create("owned-gone", "BASIC");
    TestProducers.register("owned-gone-prod", revoked.id(), "PUBLIC");
    asAdmin().post(TestUsers.ADMIN + "/" + revoked.id() + "/revoke").then().statusCode(200);

    for (var id : new UUID[] {revoked.id(), UUID.randomUUID()}) {
      asClient(admin.clientKey()).get(USERS + "/" + id + "/producers").then().statusCode(404);
    }
    // No key at all and a revoked device are refused.
    given().get(USERS + "/" + revoked.id() + "/producers").then().statusCode(401);
    asAdmin().post(TestClients.ADMIN + "/" + admin.id() + "/revoke").then().statusCode(200);
    asClient(admin.clientKey())
        .get(USERS + "/" + revoked.id() + "/producers")
        .then()
        .statusCode(401);
  }

  private static void person(
      ValidatableResponse list, UUID id, String role, int activeDevices, boolean hasPaired) {
    var item = "items.find { it.id == '" + id + "' }";
    list.body(item + ".role", equalTo(role))
        .body(item + ".activeDevices", equalTo(activeDevices))
        .body(item + ".hasPaired", equalTo(hasPaired));
  }

  @Test
  void anAdminInvitesAUserWhoPairsAFirstDevice() {
    var admin = TestClients.registerAs("ADMIN", "invite-admin");
    var name = "invited-" + UUID.randomUUID();

    var invited =
        invite(admin, Map.of("name", name, "role", "MOD", "deviceName", "Pixel 8"))
            .statusCode(201)
            .body("user.name", equalTo(name))
            .body("user.role", equalTo("MOD"))
            .body("pairing.name", equalTo("Pixel 8"))
            .body("pairing.admin", equalTo(false))
            .body("pairing.user.name", equalTo(name))
            .body("pairing.code", startsWith("shpc1_"))
            .body("pairing.uri", notNullValue());
    var userId = invited.extract().<String>path("user.id");
    var code = invited.extract().<String>path("pairing.code");
    var pairingId = invited.extract().<String>path("pairing.id");

    // The user is listed; the admin sees the code unused.
    asClient(admin.clientKey()).get(USERS).then().body("items.id", hasItem(userId));
    asClient(admin.clientKey())
        .get(CLIENT + "/pairings/" + pairingId)
        .then()
        .statusCode(200)
        .body("state", equalTo("PENDING"));

    // The code gives the invited user a device of their own, whose role is the invited one.
    var paired =
        given()
            .header("Authorization", "Bearer " + code)
            .post("/api/v1/pairing")
            .then()
            .statusCode(201)
            .body("client.user.id", equalTo(userId))
            .body("client.admin", equalTo(false))
            .extract();
    asClient(paired.<String>path("clientKey"))
        .get(CLIENT + "/devices")
        .then()
        .statusCode(200)
        .body("items.size()", equalTo(1))
        .body("items[0].user.role", equalTo("MOD"));
    asClient(admin.clientKey())
        .get(CLIENT + "/pairings/" + pairingId)
        .then()
        .body("state", equalTo("REDEEMED"));
  }

  @Test
  void anInvitationDefaultsToABasicUserAndAFirstDevice() {
    var admin = TestClients.registerAs("ADMIN", "invite-default");
    invite(admin, Map.of("name", "default-" + UUID.randomUUID()))
        .statusCode(201)
        .body("user.role", equalTo("BASIC"))
        .body("pairing.name", equalTo("First device"));
  }

  @Test
  void aNameIsUniqueIgnoringCaseAndAFailedInvitationLeavesNoUser() {
    var admin = TestClients.registerAs("ADMIN", "invite-conflict");
    var name = "Conflict-" + UUID.randomUUID();
    invite(admin, Map.of("name", name)).statusCode(201);
    invite(admin, Map.of("name", name.toLowerCase())).statusCode(409);
    // A refused invitation (here, ADMIN) creates nothing.
    var refused = "refused-" + UUID.randomUUID();
    invite(admin, Map.of("name", refused, "role", "ADMIN"))
        .statusCode(400)
        .body("violations[0].field", equalTo("role"));
    asClient(admin.clientKey()).get(USERS).then().body("items.name", not(hasItem(refused)));
    asAdmin().get(TestUsers.ADMIN).then().body("items.name", not(hasItem(refused)));
  }

  @Test
  void anInvitationIsValidated() {
    var admin = TestClients.registerAs("ADMIN", "invite-invalid");
    invite(admin, Map.of()).statusCode(400);
    invite(admin, Map.of("name", "  ")).statusCode(400);
    invite(admin, Map.of("name", "x".repeat(101))).statusCode(400);
    invite(admin, Map.of("name", "x", "role", "OWNER")).statusCode(400);
    invite(admin, Map.of("name", "x", "admin", true)).statusCode(400);
  }

  @ParameterizedTest
  @ValueSource(strings = {"BASIC", "MOD"})
  void onlyAnAdminInvitesOrSetsRolesWhateverTheBody(String role) {
    var caller = TestClients.registerAs(role, "no-admin-" + role);
    var target = TestUsers.create("no-admin-target", "BASIC");
    var name = "sneaky-" + UUID.randomUUID();

    invite(caller, Map.of("name", name)).statusCode(403);
    invite(caller, Map.of("name", name, "role", "ADMIN")).statusCode(403);
    invite(caller, Map.of()).statusCode(400);
    for (var id : new UUID[] {target.id(), caller.userId(), UUID.randomUUID()}) {
      setRole(caller, id, Map.of("role", "MOD")).statusCode(403);
      setRole(caller, id, Map.of("role", "ADMIN")).statusCode(403);
    }
    asAdmin().get(TestUsers.ADMIN).then().body("items.name", not(hasItem(name)));
    asAdmin().get(TestUsers.ADMIN + "/" + target.id()).then().body("role", equalTo("BASIC"));
    asAdmin().get(TestUsers.ADMIN + "/" + caller.userId()).then().body("role", equalTo(role));
  }

  @Test
  void anAdminSetsTheRoleOfAUserWhoIsNotAnAdminToBasicOrMod() {
    var admin = TestClients.registerAs("ADMIN", "role-admin");
    var user = TestClients.registerAs("BASIC", "role-user");

    // As a mod, the user may pair a device of their own; as a basic user, none.
    pairing(user).statusCode(403);
    setRole(admin, user.userId(), Map.of("role", "MOD"))
        .statusCode(200)
        .body("id", equalTo(user.userId().toString()))
        .body("role", equalTo("MOD"))
        .body("keySet()", org.hamcrest.Matchers.containsInAnyOrder("id", "name", "role"));
    pairing(user).statusCode(201);
    setRole(admin, user.userId(), Map.of("role", "MOD")).statusCode(200);
    setRole(admin, user.userId(), Map.of("role", "BASIC")).statusCode(200);
    pairing(user).statusCode(403);
    asAdmin().get(TestUsers.ADMIN + "/" + user.userId()).then().body("role", equalTo("BASIC"));
  }

  @Test
  void nobodyMakesAnAdminOrChangesOneFromADevice() {
    var admin = TestClients.registerAs("ADMIN", "never-admin");
    var other = TestClients.registerAs("ADMIN", "never-other-admin");
    var user = TestClients.registerAs("MOD", "never-user");

    setRole(admin, user.userId(), Map.of("role", "ADMIN")).statusCode(400);
    setRole(admin, other.userId(), Map.of("role", "BASIC")).statusCode(409);
    setRole(admin, admin.userId(), Map.of("role", "BASIC")).statusCode(409);
    setRole(admin, UUID.randomUUID(), Map.of("role", "BASIC")).statusCode(404);
    setRole(admin, user.userId(), Map.of()).statusCode(400);
    setRole(admin, user.userId(), Map.of("name", "renamed")).statusCode(400);
    asAdmin().get(TestUsers.ADMIN + "/" + other.userId()).then().body("role", equalTo("ADMIN"));
    asAdmin().get(TestUsers.ADMIN + "/" + user.userId()).then().body("role", equalTo("MOD"));

    // A revoked user is not changed.
    var revoked = TestUsers.create("never-revoked", "BASIC");
    asAdmin().post(TestUsers.ADMIN + "/" + revoked.id() + "/revoke").then().statusCode(200);
    setRole(admin, revoked.id(), Map.of("role", "MOD")).statusCode(409);
  }

  @Test
  void aDemotedAdminCannotInviteAnyMoreAndNoKeyOtherThanAClientKeyWorks() {
    var admin = TestClients.registerAs("ADMIN", "demoted");
    invite(admin, Map.of("name", "before-" + UUID.randomUUID())).statusCode(201);
    asAdmin()
        .contentType(ContentType.JSON)
        .body(Map.of("role", "MOD"))
        .patch(TestUsers.ADMIN + "/" + admin.userId())
        .then()
        .statusCode(200);
    invite(admin, Map.of("name", "after-" + UUID.randomUUID())).statusCode(403);

    given().get(USERS).then().statusCode(401);
    given().header("Authorization", "Bearer " + adminToken()).get(USERS).then().statusCode(401);
    given()
        .header("Authorization", "Bearer " + adminToken())
        .contentType(ContentType.JSON)
        .body(Map.of("name", "x"))
        .post(USERS)
        .then()
        .statusCode(401);
    asAdmin().get(CLIENT + "/users").then().statusCode(401);
  }

  @Test
  void aRevokedDeviceOrUserCannotInvite() {
    var admin = TestClients.registerAs("ADMIN", "revoked-inviter");
    asAdmin().post("/api/v1/admin/clients/" + admin.id() + "/revoke").then().statusCode(200);
    invite(admin, Map.of("name", "late-" + UUID.randomUUID())).statusCode(401);
    asClient(admin.clientKey()).get(USERS).then().statusCode(401);
  }

  private static ValidatableResponse invite(Registered caller, Map<String, ?> body) {
    return asClient(caller.clientKey()).contentType(ContentType.JSON).body(body).post(USERS).then();
  }

  private static ValidatableResponse setRole(Registered caller, UUID id, Map<String, ?> body) {
    return asClient(caller.clientKey())
        .contentType(ContentType.JSON)
        .body(body)
        .patch(USERS + "/" + id)
        .then();
  }

  private static ValidatableResponse pairing(Registered caller) {
    return asClient(caller.clientKey())
        .contentType(ContentType.JSON)
        .body(Map.of("name", "second device"))
        .post(CLIENT + "/pairings")
        .then();
  }
}
