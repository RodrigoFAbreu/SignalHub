package io.github.rodrigofabreu.signalhub.client;

import static io.github.rodrigofabreu.signalhub.TestClients.ADMIN;
import static io.github.rodrigofabreu.signalhub.TestClients.CLIENT;
import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.hasKey;
import static org.hamcrest.Matchers.not;
import static org.hamcrest.Matchers.notNullValue;
import static org.hamcrest.Matchers.nullValue;
import static org.junit.jupiter.api.Assertions.assertEquals;

import io.github.rodrigofabreu.signalhub.TestClients;
import io.github.rodrigofabreu.signalhub.TestClients.Registered;
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
 * Managing devices from an admin device, against real PostgreSQL: every caller (an ordinary client,
 * an admin, a revoked admin) with every target (an ordinary client, an admin, itself, a revoked
 * client, an unknown ID).
 */
@QuarkusTest
class DeviceApiTest {

  private static final String DEVICES = CLIENT + "/devices";

  /** The client a request is about, relative to the caller. */
  enum Target {
    ORDINARY,
    ADMIN,
    ITSELF,
    REVOKED,
    UNKNOWN
  }

  @ParameterizedTest
  @EnumSource(Target.class)
  void aClientThatIsNotAnAdminIsRefusedWhateverTheTarget(Target target) {
    var caller = TestClients.register("ordinary-caller");
    var id = target(target, caller);

    forbidden(makeAdmin(caller, id));
    forbidden(revoke(caller, id));
    forbidden(asClient(caller.clientKey()).get(DEVICES).then());

    // Nothing changed: the caller is still no admin and the target still as it was.
    asAdmin().get(ADMIN + "/" + caller.id()).then().body("admin", equalTo(false));
    if (target != Target.UNKNOWN) {
      asAdmin()
          .get(ADMIN + "/" + id)
          .then()
          .body("admin", equalTo(target == Target.ADMIN))
          .body("revokedAt", target == Target.REVOKED ? notNullValue() : nullValue());
    }
  }

  @ParameterizedTest
  @EnumSource(Target.class)
  void aRevokedAdminIsNotAuthenticatedWhateverTheTarget(Target target) {
    var caller = TestClients.registerAdmin("revoked-admin-caller");
    var id = target(target, caller);
    asAdmin().post(ADMIN + "/" + caller.id() + "/revoke").then().statusCode(200);

    makeAdmin(caller, id).statusCode(401);
    revoke(caller, id).statusCode(401);
    asClient(caller.clientKey()).get(DEVICES).then().statusCode(401);
  }

  @Test
  void anAdminListsEveryDeviceWithoutKeysOrPushTokens() {
    var caller = TestClients.registerAdmin("listing-admin");
    var other = TestClients.register("listed-device");
    var token = "listed-" + UUID.randomUUID();
    asClient(other.clientKey())
        .contentType(ContentType.JSON)
        .body(Map.of("provider", FakePushProvider.NAME, "token", token))
        .put(CLIENT + "/push-target")
        .then()
        .statusCode(200);
    var gone = TestClients.register("listed-revoked");
    asAdmin().post(ADMIN + "/" + gone.id() + "/revoke").then().statusCode(200);

    var listed = asClient(caller.clientKey()).get(DEVICES).then().statusCode(200);

    var device = "items.find { it.id == '" + other.id() + "' }";
    listed
        .body(device + ".name", equalTo("listed-device"))
        .body(device + ".admin", equalTo(false))
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
  void anAdminMakesAnOrdinaryDeviceAnAdmin() {
    var caller = TestClients.registerAdmin("granting-admin");
    var target = TestClients.register("to-be-admin");

    makeAdmin(caller, target.id())
        .statusCode(200)
        .body("id", equalTo(target.id().toString()))
        .body("admin", equalTo(true))
        .body("name", equalTo("to-be-admin"))
        .body("pushStatus", notNullValue());

    asClient(target.clientKey()).get(CLIENT).then().body("admin", equalTo(true));
    // The new admin can now manage devices itself.
    asClient(target.clientKey()).get(DEVICES).then().statusCode(200);
  }

  @Test
  void makingAnAdminAnAdminChangesNothing() {
    var caller = TestClients.registerAdmin("admin-granting-admin");
    var other = TestClients.registerAdmin("already-admin");

    makeAdmin(caller, other.id()).statusCode(200).body("admin", equalTo(true));
    makeAdmin(caller, caller.id())
        .statusCode(200)
        .body("admin", equalTo(true))
        .body("revokedAt", nullValue());
  }

  @Test
  void aRevokedDeviceCannotBeMadeAnAdmin() {
    var caller = TestClients.registerAdmin("admin-and-revoked");
    var gone = revoked("revoked-target");

    makeAdmin(caller, gone.id())
        .statusCode(409)
        .body("title", equalTo("Client is revoked"))
        .body("status", equalTo(409));
    asAdmin().get(ADMIN + "/" + gone.id()).then().body("admin", equalTo(false));
  }

  @Test
  void anAdminRevokesAnOrdinaryDevice() {
    var caller = TestClients.registerAdmin("revoking-admin");
    var target = TestClients.register("to-be-revoked");
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

  @Test
  void revokingARevokedDeviceChangesNothing() {
    var caller = TestClients.registerAdmin("admin-revoking-again");
    var gone = revoked("already-revoked");
    String revokedAt = asAdmin().get(ADMIN + "/" + gone.id()).then().extract().path("revokedAt");

    revoke(caller, gone.id()).statusCode(200).body("revokedAt", equalTo(revokedAt));
  }

  @Test
  void anAdminCannotRevokeAnotherAdmin() {
    var caller = TestClients.registerAdmin("admin-revoking-admin");
    var other = TestClients.registerAdmin("protected-admin");

    revoke(caller, other.id())
        .statusCode(409)
        .body("title", equalTo("Client is an admin device"))
        .body("status", equalTo(409));
    asClient(other.clientKey()).get(CLIENT).then().statusCode(200).body("admin", equalTo(true));
  }

  @Test
  void anAdminCannotRevokeItself() {
    var caller = TestClients.registerAdmin("self-revoking-admin");

    revoke(caller, caller.id()).statusCode(409).body("title", equalTo("Client is an admin device"));
    asClient(caller.clientKey()).get(CLIENT).then().statusCode(200);
  }

  @Test
  void anUnknownDeviceIsNotFound() {
    var caller = TestClients.registerAdmin("admin-with-unknown-target");
    var unknown = UUID.randomUUID();

    makeAdmin(caller, unknown).statusCode(404).body("status", equalTo(404));
    revoke(caller, unknown).statusCode(404).body("status", equalTo(404));
  }

  @Test
  void aDeviceWhoseAdminRightsWereTakenAwayIsRefused() {
    var caller = TestClients.registerAdmin("former-admin");
    var target = TestClients.register("target-of-former-admin");
    asAdmin()
        .contentType(ContentType.JSON)
        .body("{\"admin\": false}")
        .patch(ADMIN + "/" + caller.id())
        .then()
        .statusCode(200);

    forbidden(makeAdmin(caller, target.id()));
    forbidden(revoke(caller, target.id()));
    forbidden(asClient(caller.clientKey()).get(DEVICES).then());
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
    var caller = TestClients.registerAdmin("admin-with-invalid-id");

    makeAdmin(caller, "not-a-uuid").statusCode(404);
  }

  private static UUID target(Target target, Registered caller) {
    return switch (target) {
      case ORDINARY -> TestClients.register("ordinary-target").id();
      case ADMIN -> TestClients.registerAdmin("admin-target").id();
      case ITSELF -> caller.id();
      case REVOKED -> revoked("revoked-target").id();
      case UNKNOWN -> UUID.randomUUID();
    };
  }

  private static Registered revoked(String name) {
    var client = TestClients.register(name);
    asAdmin().post(ADMIN + "/" + client.id() + "/revoke").then().statusCode(200);
    return client;
  }

  private static ValidatableResponse makeAdmin(Registered caller, Object id) {
    return asClient(caller.clientKey()).post(DEVICES + "/" + id + "/admin").then();
  }

  private static ValidatableResponse revoke(Registered caller, UUID id) {
    return asClient(caller.clientKey()).post(DEVICES + "/" + id + "/revoke").then();
  }

  private static void forbidden(ValidatableResponse response) {
    response
        .statusCode(403)
        .body("title", equalTo("Not an admin device"))
        .body("status", equalTo(403))
        .body("violations.size()", equalTo(0));
  }
}
