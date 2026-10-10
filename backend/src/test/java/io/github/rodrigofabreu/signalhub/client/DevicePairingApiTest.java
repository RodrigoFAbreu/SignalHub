package io.github.rodrigofabreu.signalhub.client;

import static io.github.rodrigofabreu.signalhub.TestClients.ADMIN;
import static io.github.rodrigofabreu.signalhub.TestClients.CLIENT;
import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.notNullValue;
import static org.hamcrest.Matchers.nullValue;
import static org.hamcrest.Matchers.startsWith;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

import io.agroal.api.AgroalDataSource;
import io.github.rodrigofabreu.signalhub.TestClients;
import io.github.rodrigofabreu.signalhub.TestClients.Registered;
import io.github.rodrigofabreu.signalhub.TestUsers;
import io.github.rodrigofabreu.signalhub.producer.ApiKeys;
import io.github.rodrigofabreu.signalhub.push.DeviceNotifier;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import io.restassured.response.ValidatableResponse;
import jakarta.inject.Inject;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.sql.SQLException;
import java.time.Duration;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/**
 * Creating pairing codes from a device, against real PostgreSQL, as its user's role allows (a basic
 * user none, a mod for themselves, an admin for anyone), for a device of the user the code is for,
 * only as long as the device that created the code may still create it; and whether a code it
 * created was used, for that device only.
 */
@QuarkusTest
class DevicePairingApiTest {

  static final String PAIRINGS = CLIENT + "/pairings";

  @Inject AgroalDataSource dataSource;
  @Inject DeviceNotifier notifier;

  // Each redemption pushes a notice to the clients other tests gave push targets; it must be sent
  // before those tests count their pushes.
  @AfterEach
  void awaitNotices() throws Exception {
    notifier.awaitSent(Duration.ofSeconds(10));
  }

  @Test
  void aDeviceCreatesAPairingForItsOwnUserByDefault() throws SQLException {
    var caller = TestClients.registerAs("ADMIN", "pairing-admin");

    var pairing =
        create(caller, "Tablet")
            .statusCode(201)
            .header("Location", nullValue())
            .body("name", equalTo("Tablet"))
            // An admin's device is an admin device.
            .body("admin", equalTo(true))
            .body("user.id", equalTo(caller.userId().toString()))
            .body("code", startsWith(PairingCodes.PREFIX))
            .body("id", notNullValue())
            .extract();
    String code = pairing.path("code");

    assertEquals(
        "signalhub://pair?server="
            + URLEncoder.encode("https://signalhub.example.test", StandardCharsets.UTF_8)
            + "&code="
            + code,
        pairing.path("uri"));
    assertEquals(caller.id(), createdBy(code));

    var issued =
        redeem(code)
            .statusCode(201)
            .body("client.name", equalTo("Tablet"))
            .body("client.admin", equalTo(true))
            .body("client.user.id", equalTo(caller.userId().toString()))
            .extract();
    asClient(issued.path("clientKey")).get(CLIENT).then().statusCode(200);
    redeem(code).statusCode(401);
  }

  @Test
  void anAdminCreatesAPairingForAnotherUser() {
    var caller = TestClients.registerAs("ADMIN", "pairing-for-others");
    var user = TestUsers.create("pairing-target", "MOD");

    var code =
        createFor(caller, "Her phone", user.id())
            .statusCode(201)
            .body("admin", equalTo(false))
            .body("user.id", equalTo(user.id().toString()))
            .body("user.role", equalTo("MOD"))
            .extract()
            .<String>path("code");

    redeem(code)
        .statusCode(201)
        .body("client.admin", equalTo(false))
        .body("client.user.id", equalTo(user.id().toString()));
  }

  @Test
  void aModCreatesAPairingOnlyForThemselves() throws SQLException {
    var caller = TestClients.registerAs("MOD", "pairing-mod");
    var other = TestUsers.create("pairing-mod-other", "BASIC");

    create(caller, "Own tablet")
        .statusCode(201)
        .body("admin", equalTo(false))
        .body("user.id", equalTo(caller.userId().toString()));
    createFor(caller, "Own, named", caller.userId()).statusCode(201);
    createFor(caller, "Someone else's " + caller.id(), other.id())
        .statusCode(403)
        .body("title", equalTo("Not allowed for your role"));
    createFor(caller, "Nobody's " + caller.id(), UUID.randomUUID()).statusCode(403);
    assertEquals(0, pairingsFor("Someone else's " + caller.id()));
  }

  @Test
  void anAdminCannotCreateAPairingForAUnknownOrRevokedUser() {
    var caller = TestClients.registerAs("ADMIN", "pairing-unknown-user");
    var gone = TestUsers.create("pairing-revoked-user", "BASIC");
    asAdmin().post(TestUsers.ADMIN + "/" + gone.id() + "/revoke").then().statusCode(200);

    createFor(caller, "Nobody's", UUID.randomUUID()).statusCode(404);
    createFor(caller, "Revoked's", gone.id()).statusCode(409);
  }

  @Test
  void aBasicUserIsRefused() throws SQLException {
    var caller = TestClients.registerAs("BASIC", "basic-pairing-caller");

    create(caller, "Refused " + caller.id())
        .statusCode(403)
        .body("title", equalTo("Not allowed for your role"))
        .body("status", equalTo(403))
        .body("violations.size()", equalTo(0));

    assertEquals(0, pairingsFor("Refused " + caller.id()));
  }

  @Test
  void aDeviceWhoseUserWasMadeBasicIsRefused() {
    var caller = TestClients.registerAs("ADMIN", "former-pairing-admin");
    setRole(caller, "BASIC");

    create(caller, "Refused").statusCode(403).body("title", equalTo("Not allowed for your role"));
  }

  @Test
  void aRevokedAdminIsNotAuthenticated() throws SQLException {
    var caller = TestClients.registerAs("ADMIN", "revoked-pairing-admin");
    asAdmin().post(ADMIN + "/" + caller.id() + "/revoke").then().statusCode(200);

    create(caller, "Refused " + caller.id()).statusCode(401).body("title", equalTo("Unauthorized"));

    assertEquals(0, pairingsFor("Refused " + caller.id()));
  }

  @Test
  void theEndpointNeedsAClientKey() {
    given()
        .contentType(ContentType.JSON)
        .body("{\"name\": \"x\"}")
        .post(PAIRINGS)
        .then()
        .statusCode(401);
    // The admin token is not a client key: the operator has the management API.
    asAdmin()
        .contentType(ContentType.JSON)
        .body("{\"name\": \"x\"}")
        .post(PAIRINGS)
        .then()
        .statusCode(401);
  }

  @ParameterizedTest
  @ValueSource(
      strings = {
        "{}",
        "{\"name\": \" \"}",
        "{\"name\": \"a\\u0000b\"}",
        "{\"name\": 1}",
        // Roles are set per user: a device cannot say whether the new one is an admin device.
        "{\"name\": \"x\", \"admin\": true}",
        "{\"name\": \"x\", \"admin\": false}",
      })
  void invalidPairingsAreRejected(String body) {
    var caller = TestClients.registerAs("ADMIN", "admin-with-invalid-pairing");

    asClient(caller.clientKey())
        .contentType(ContentType.JSON)
        .body(body)
        .post(PAIRINGS)
        .then()
        .statusCode(400);
  }

  @Test
  void aNameOfMoreThan100CharactersIsRejected() {
    var caller = TestClients.registerAs("ADMIN", "admin-with-long-name");

    create(caller, "x".repeat(101)).statusCode(400);
    create(caller, "x".repeat(100)).statusCode(201);
  }

  @Test
  void theCodeStopsWorkingOnceItsDeviceIsRevoked() throws SQLException {
    var caller = TestClients.registerAs("ADMIN", "stolen-admin");
    String code = create(caller, "Stolen code").statusCode(201).extract().path("code");

    asAdmin().post(ADMIN + "/" + caller.id() + "/revoke").then().statusCode(200);

    redeem(code).statusCode(401).body("title", equalTo("Unauthorized"));
    assertEquals(0, clientsNamed("Stolen code"));
    // Deleted, since it can never redeem again.
    assertEquals(0, pairingsFor("Stolen code"));
  }

  @Test
  void theCodeStopsWorkingOnceItsUserMayNoLongerCreateIt() throws SQLException {
    var caller = TestClients.registerAs("ADMIN", "demoted-admin");
    var user = TestUsers.create("demoted-admin-target", "BASIC");
    String code =
        createFor(caller, "Demoted code", user.id()).statusCode(201).extract().path("code");

    // A mod pairs only for themselves, so the admin's code for someone else is void.
    setRole(caller, "MOD");

    redeem(code).statusCode(401);
    assertEquals(0, clientsNamed("Demoted code"));
    // Made an admin again, the old code still does not come back.
    setRole(caller, "ADMIN");
    redeem(code).statusCode(401);
  }

  @Test
  void theCodeStopsWorkingOnceItsUserIsRevoked() throws SQLException {
    var caller = TestClients.registerAs("ADMIN", "inviting-admin");
    var user = TestUsers.create("revoked-before-redeeming", "MOD");
    String code = createFor(caller, "Late code", user.id()).statusCode(201).extract().path("code");

    asAdmin().post(TestUsers.ADMIN + "/" + user.id() + "/revoke").then().statusCode(200);

    redeem(code).statusCode(401);
    assertEquals(0, clientsNamed("Late code"));
  }

  @Test
  void aPairingFromTheAdminTokenHasNoCreator() throws SQLException {
    String code =
        asAdmin()
            .contentType(ContentType.JSON)
            .body(Map.of("name", "Operator's pairing"))
            .post("/api/v1/admin/pairings")
            .then()
            .statusCode(201)
            .extract()
            .path("code");

    assertNull(createdBy(code));
  }

  @Test
  void anAdminDeviceLearnsThatItsCodeWasUsedAndByWhichDevice() throws SQLException {
    var caller = TestClients.registerAs("ADMIN", "pairing-watcher");
    var pairing = create(caller, "Watched tablet").statusCode(201).extract();
    String id = pairing.path("id");

    status(caller, id)
        .statusCode(200)
        .body("id", equalTo(id))
        .body("state", equalTo("PENDING"))
        .body("client", nullValue());

    String clientId = redeem(pairing.path("code")).statusCode(201).extract().path("client.id");

    status(caller, id)
        .statusCode(200)
        .body("state", equalTo("REDEEMED"))
        .body("redeemedAt", notNullValue())
        .body("client.id", equalTo(clientId))
        .body("client.name", equalTo("Watched tablet"));
    // Used once, and kept only to say so.
    redeem(pairing.path("code")).statusCode(401);
    assertEquals(1, clientsNamed("Watched tablet"));
  }

  @Test
  void anExpiredCodeOfTheDeviceSaysSo() throws SQLException {
    var caller = TestClients.registerAs("ADMIN", "expired-pairing-watcher");
    var pairing = create(caller, "Late tablet").statusCode(201).extract();
    expire(pairing.path("code"));

    status(caller, pairing.path("id")).statusCode(200).body("state", equalTo("EXPIRED"));
  }

  @Test
  void anotherDevicesCodeIsUnknown() {
    var creator = TestClients.registerAs("ADMIN", "pairing-owner");
    var other = TestClients.registerAs("ADMIN", "pairing-snoop");
    String id = create(creator, "Someone else's").statusCode(201).extract().path("id");

    status(other, id).statusCode(404).body("title", equalTo("Not found"));
    status(other, UUID.randomUUID().toString()).statusCode(404).body("title", equalTo("Not found"));
    status(creator, id).statusCode(200);
  }

  @Test
  void theOperatorsCodeIsUnknownToADevice() {
    var caller = TestClients.registerAs("ADMIN", "operator-pairing-snoop");
    String id =
        asAdmin()
            .contentType(ContentType.JSON)
            .body(Map.of("name", "Operator's code"))
            .post("/api/v1/admin/pairings")
            .then()
            .statusCode(201)
            .extract()
            .path("id");

    status(caller, id).statusCode(404);
  }

  @Test
  void onlyAnActiveModOrAdminDeviceAsks() {
    var creator = TestClients.registerAs("ADMIN", "pairing-status-admin");
    String id = create(creator, "Asked about").statusCode(201).extract().path("id");
    var basic = TestClients.registerAs("BASIC", "basic-pairing-status-caller");

    // Refused before the pairing is looked up: the same for a known and an unknown ID.
    status(basic, id).statusCode(403).body("title", equalTo("Not allowed for your role"));
    status(basic, UUID.randomUUID().toString())
        .statusCode(403)
        .body("title", equalTo("Not allowed for your role"));
    given().get(PAIRINGS + "/" + id).then().statusCode(401);
    asAdmin().get(PAIRINGS + "/" + id).then().statusCode(401);

    setRole(creator, "BASIC");
    status(creator, id).statusCode(403);
    setRole(creator, "ADMIN");
    asAdmin().post(ADMIN + "/" + creator.id() + "/revoke").then().statusCode(200);
    status(creator, id).statusCode(401);
  }

  private static ValidatableResponse status(Registered caller, String id) {
    return asClient(caller.clientKey()).get(PAIRINGS + "/" + id).then();
  }

  private void expire(String code) throws SQLException {
    try (var connection = dataSource.getConnection();
        var statement =
            connection.prepareStatement(
                "UPDATE pairings SET created_at = created_at - interval '11 minutes',"
                    + " expires_at = expires_at - interval '11 minutes' WHERE code_hash = ?")) {
      statement.setBytes(1, ApiKeys.hash(code));
      assertEquals(1, statement.executeUpdate());
    }
  }

  private static ValidatableResponse create(Registered caller, String name) {
    return asClient(caller.clientKey())
        .contentType(ContentType.JSON)
        .body(Map.of("name", name))
        .post(PAIRINGS)
        .then();
  }

  private static ValidatableResponse redeem(String code) {
    return given().header("Authorization", "Bearer " + code).post("/api/v1/pairing").then();
  }

  private static void setRole(Registered client, String role) {
    asAdmin()
        .contentType(ContentType.JSON)
        .body(Map.of("role", role))
        .patch(TestUsers.ADMIN + "/" + client.userId())
        .then()
        .statusCode(200);
  }

  private static ValidatableResponse createFor(Registered caller, String name, UUID userId) {
    return asClient(caller.clientKey())
        .contentType(ContentType.JSON)
        .body(Map.of("name", name, "userId", userId.toString()))
        .post(PAIRINGS)
        .then();
  }

  private UUID createdBy(String code) throws SQLException {
    try (var connection = dataSource.getConnection();
        var statement =
            connection.prepareStatement("SELECT created_by FROM pairings WHERE code_hash = ?")) {
      statement.setBytes(1, ApiKeys.hash(code));
      try (var row = statement.executeQuery()) {
        row.next();
        return row.getObject(1, UUID.class);
      }
    }
  }

  private long pairingsFor(String name) throws SQLException {
    return count("SELECT count(*) FROM pairings WHERE client_name = ?", name);
  }

  private long clientsNamed(String name) throws SQLException {
    return count("SELECT count(*) FROM clients WHERE name = ?", name);
  }

  private long count(String query, String parameter) throws SQLException {
    try (var connection = dataSource.getConnection();
        var statement = connection.prepareStatement(query)) {
      statement.setString(1, parameter);
      try (var row = statement.executeQuery()) {
        row.next();
        return row.getLong(1);
      }
    }
  }
}
