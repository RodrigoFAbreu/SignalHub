package io.github.rodrigofabreu.signalhub.client;

import static io.github.rodrigofabreu.signalhub.TestClients.ADMIN;
import static io.github.rodrigofabreu.signalhub.TestClients.CLIENT;
import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.containsInAnyOrder;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.hasKey;
import static org.hamcrest.Matchers.not;
import static org.hamcrest.Matchers.notNullValue;
import static org.hamcrest.Matchers.nullValue;
import static org.junit.jupiter.api.Assertions.assertEquals;

import io.github.rodrigofabreu.signalhub.TestClients;
import io.github.rodrigofabreu.signalhub.TestClients.Registered;
import io.github.rodrigofabreu.signalhub.TestUsers;
import io.github.rodrigofabreu.signalhub.push.FakePushProvider;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import io.restassured.response.ValidatableResponse;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;

/**
 * Managing devices from a device, against real PostgreSQL: what each role may do (a basic user
 * nothing, a mod their own devices, an admin those of users who are not admins), with every target
 * (a device of another user, an admin's, itself, a revoked one, an unknown ID).
 */
@QuarkusTest
class DeviceApiTest {

  private static final String DEVICES = CLIENT + "/devices";

  /** The client a request is about, relative to the caller. */
  enum Target {
    OTHER_USERS,
    ADMINS,
    ITSELF,
    REVOKED,
    UNKNOWN
  }

  @ParameterizedTest
  @EnumSource(Target.class)
  void aBasicUserChangesNoDeviceWhateverTheTarget(Target target) {
    var caller = TestClients.registerAs("BASIC", "basic-caller");
    var id = target(target, caller);

    forbidden(revoke(caller, id));
    forbidden(delete(caller, id));

    // Nothing changed: the caller still works and the target is as it was.
    asClient(caller.clientKey()).get(CLIENT).then().statusCode(200);
    if (target != Target.UNKNOWN) {
      asAdmin()
          .get(ADMIN + "/" + id)
          .then()
          .body("revokedAt", target == Target.REVOKED ? notNullValue() : nullValue());
    }
  }

  @ParameterizedTest
  @EnumSource(Target.class)
  void aRevokedDeviceIsNotAuthenticatedWhateverItsRoleOrTheTarget(Target target) {
    for (var role : new String[] {"BASIC", "MOD", "ADMIN"}) {
      var caller = TestClients.registerAs(role, "revoked-" + role);
      var id = target(target, caller);
      asAdmin().post(ADMIN + "/" + caller.id() + "/revoke").then().statusCode(200);

      revoke(caller, id).statusCode(401);
      delete(caller, id).statusCode(401);
      asClient(caller.clientKey()).get(DEVICES).then().statusCode(401);
    }
  }

  @Test
  void aBasicUserAndAModListOnlyTheirOwnDevices() {
    for (var role : new String[] {"BASIC", "MOD"}) {
      var caller = TestClients.registerAs(role, role + "-listing");
      var second = TestClients.registerFor(caller.userId(), role + "-second");
      var stranger = TestClients.register("not-theirs-" + role);

      asClient(caller.clientKey())
          .get(DEVICES)
          .then()
          .body("items.id", containsInAnyOrder(caller.id().toString(), second.id().toString()))
          .body("items.id", not(hasItem(stranger.id().toString())));
    }
  }

  @Test
  void anAdminListsEveryDeviceWithoutKeysOrPushTokens() {
    var caller = TestClients.registerAs("ADMIN", "listing-admin");
    var other = TestClients.registerAs("MOD", "listed-device");
    var token = "listed-" + UUID.randomUUID();
    asClient(other.clientKey())
        .contentType(ContentType.JSON)
        .body(Map.of("provider", FakePushProvider.NAME, "token", token))
        .put(CLIENT + "/push-target")
        .then()
        .statusCode(200);
    var gone = TestClients.registerAs("BASIC", "listed-revoked");
    asAdmin().post(ADMIN + "/" + gone.id() + "/revoke").then().statusCode(200);

    var listed = asClient(caller.clientKey()).get(DEVICES).then().statusCode(200);

    var device = "items.find { it.id == '" + other.id() + "' }";
    listed
        .body(device + ".name", equalTo("listed-device"))
        .body(device + ".admin", equalTo(false))
        .body(device + ".user.role", equalTo("MOD"))
        .body(device + ".pushTarget.provider", equalTo(FakePushProvider.NAME))
        .body(device + ".pushTarget", not(hasKey("token")))
        .body(device + ".pushStatus.pendingRetries", equalTo(0))
        .body(device, not(hasKey("clientKey")))
        .body("items.find { it.id == '" + caller.id() + "' }.admin", equalTo(true))
        .body("items.find { it.id == '" + gone.id() + "' }.revokedAt", notNullValue());
    // The same list the operator reads.
    List<String> ids = listed.extract().path("items.id");
    List<String> operators = asAdmin().get(ADMIN).then().extract().path("items.id");
    assertEquals(operators, ids);
  }

  @Test
  void makingADeviceAnAdminIsRefusedWhoeverAsks() {
    var target = TestClients.registerAs("MOD", "never-promoted");
    for (var role : new String[] {"BASIC", "MOD", "ADMIN"}) {
      var caller = TestClients.registerAs(role, "promoting-" + role);

      makeAdmin(caller, target.id())
          .statusCode(409)
          .body("title", equalTo("Roles are set per user, not per device"))
          .body("status", equalTo(409));
      makeAdmin(caller, UUID.randomUUID()).statusCode(409);
    }
    asClient(target.clientKey()).get(CLIENT).then().body("admin", equalTo(false));
  }

  @Test
  void anAdminRevokesTheDeviceOfAUserWhoIsNotAnAdmin() {
    var caller = TestClients.registerAs("ADMIN", "revoking-admin");
    for (var role : new String[] {"BASIC", "MOD"}) {
      var target = TestClients.registerAs(role, "to-be-revoked-" + role);
      asClient(target.clientKey())
          .contentType(ContentType.JSON)
          .body(Map.of("provider", FakePushProvider.NAME, "token", "revoked-" + UUID.randomUUID()))
          .put(CLIENT + "/push-target")
          .then()
          .statusCode(200);

      revoke(caller, target.id())
          .statusCode(200)
          .body("id", equalTo(target.id().toString()))
          .body("revokedAt", notNullValue())
          .body("pushTarget", nullValue())
          .body("admin", equalTo(false));

      asClient(target.clientKey()).get(CLIENT).then().statusCode(401);
    }
  }

  @Test
  void revokingARevokedDeviceChangesNothing() {
    var caller = TestClients.registerAs("ADMIN", "admin-revoking-again");
    var gone = revoked("already-revoked");
    String revokedAt = asAdmin().get(ADMIN + "/" + gone.id()).then().extract().path("revokedAt");

    revoke(caller, gone.id()).statusCode(200).body("revokedAt", equalTo(revokedAt));
  }

  @Test
  void anAdminCannotRevokeAnAdminsDeviceItsOwnIncluded() {
    var caller = TestClients.registerAs("ADMIN", "admin-revoking-admin");
    var other = TestClients.registerAs("ADMIN", "protected-admin");

    revoke(caller, other.id())
        .statusCode(409)
        .body("title", equalTo("Client is an admin device"))
        .body("status", equalTo(409));
    revoke(caller, caller.id()).statusCode(409).body("title", equalTo("Client is an admin device"));
    // Not even a second device of the same admin.
    var second = TestClients.registerFor(caller.userId(), "second");
    revoke(caller, second.id()).statusCode(409);
    asClient(other.clientKey()).get(CLIENT).then().statusCode(200).body("admin", equalTo(true));
    asClient(caller.clientKey()).get(CLIENT).then().statusCode(200);
  }

  @Test
  void aModRevokesTheirOwnDevicesButNotTheLastActiveOne() {
    var first = TestClients.registerAs("MOD", "mod-first");
    var second = TestClients.registerFor(first.userId(), "mod-second");

    // Revoking the device that asks is allowed while another is active.
    revoke(first, second.id()).statusCode(200).body("revokedAt", notNullValue());
    asClient(second.clientKey()).get(CLIENT).then().statusCode(401);

    revoke(first, first.id())
        .statusCode(409)
        .body("title", equalTo("Cannot revoke the last active device of a user"));
    asClient(first.clientKey()).get(CLIENT).then().statusCode(200);

    // A new device makes the first one no longer the last.
    var third = TestClients.registerFor(first.userId(), "mod-third");
    revoke(third, first.id()).statusCode(200);
    asClient(first.clientKey()).get(CLIENT).then().statusCode(401);
    revoke(third, third.id()).statusCode(409);
  }

  @Test
  void aModTouchesNoDeviceOfAnotherUser() {
    var mod = TestClients.registerAs("MOD", "mod-alone");
    var basic = TestClients.registerAs("BASIC", "other-basic");
    var admin = TestClients.registerAs("ADMIN", "other-admin");
    var gone = revoked("someone-elses-revoked");

    for (var target : List.of(basic, admin, gone)) {
      // As if it did not exist: a mod learns nothing about devices that are not theirs.
      revoke(mod, target.id()).statusCode(404).body("status", equalTo(404));
      delete(mod, target.id()).statusCode(404);
    }
    asClient(basic.clientKey()).get(CLIENT).then().statusCode(200);
    asClient(admin.clientKey()).get(CLIENT).then().statusCode(200);
    asAdmin().get(ADMIN + "/" + gone.id()).then().statusCode(200);
  }

  @Test
  void anUnknownDeviceIsNotFound() {
    for (var role : new String[] {"MOD", "ADMIN"}) {
      var caller = TestClients.registerAs(role, "with-unknown-target-" + role);
      revoke(caller, UUID.randomUUID()).statusCode(404).body("status", equalTo(404));
    }
  }

  @Test
  void aDeviceWhoseUserWasMadeLessThanAnAdminLosesTheRights() {
    var caller = TestClients.registerAs("ADMIN", "former-admin");
    var target = TestClients.registerAs("MOD", "target-of-former-admin");
    asAdmin()
        .contentType(ContentType.JSON)
        .body("{\"role\": \"MOD\"}")
        .patch(TestUsers.ADMIN + "/" + caller.userId())
        .then()
        .statusCode(200);

    // A mod now: only their own devices are theirs.
    revoke(caller, target.id()).statusCode(404);
    asClient(caller.clientKey())
        .get(DEVICES)
        .then()
        .statusCode(200)
        .body("items.id", containsInAnyOrder(caller.id().toString()));
    asClient(caller.clientKey()).get(CLIENT).then().body("admin", equalTo(false));
    asClient(target.clientKey()).get(CLIENT).then().statusCode(200);
  }

  @Test
  void theEndpointsNeedAClientKey() {
    var target = TestClients.register("needs-a-key");

    given().get(DEVICES).then().statusCode(401);
    given().post(DEVICES + "/" + target.id() + "/admin").then().statusCode(401);
    given().post(DEVICES + "/" + target.id() + "/revoke").then().statusCode(401);
    // The admin token is not a client key: the operator has the management API.
    asAdmin().get(DEVICES).then().statusCode(401);
    asAdmin().post(DEVICES + "/" + target.id() + "/revoke").then().statusCode(401);
    asAdmin().get(ADMIN + "/" + target.id()).then().body("revokedAt", nullValue());
  }

  @Test
  void anInvalidIdIsNotFound() {
    var caller = TestClients.registerAs("ADMIN", "admin-with-invalid-id");

    asClient(caller.clientKey()).post(DEVICES + "/not-a-uuid/revoke").then().statusCode(404);
  }

  private static UUID target(Target target, Registered caller) {
    return switch (target) {
      case OTHER_USERS -> TestClients.registerAs("MOD", "other-target").id();
      case ADMINS -> TestClients.registerAs("ADMIN", "admin-target").id();
      case ITSELF -> caller.id();
      case REVOKED -> revoked("revoked-target").id();
      case UNKNOWN -> UUID.randomUUID();
    };
  }

  private static Registered revoked(String name) {
    var client = TestClients.registerAs("MOD", name);
    asAdmin().post(ADMIN + "/" + client.id() + "/revoke").then().statusCode(200);
    return client;
  }

  private static ValidatableResponse makeAdmin(Registered caller, Object id) {
    return asClient(caller.clientKey()).post(DEVICES + "/" + id + "/admin").then();
  }

  private static ValidatableResponse revoke(Registered caller, UUID id) {
    return asClient(caller.clientKey()).post(DEVICES + "/" + id + "/revoke").then();
  }

  private static ValidatableResponse delete(Registered caller, UUID id) {
    return asClient(caller.clientKey()).delete(DEVICES + "/" + id).then();
  }

  private static void forbidden(ValidatableResponse response) {
    response
        .statusCode(403)
        .body("title", equalTo("Not allowed for your role"))
        .body("status", equalTo(403))
        .body("violations.size()", equalTo(0));
  }
}
