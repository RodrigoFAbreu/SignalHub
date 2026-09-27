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
 * Creating pairing codes from an admin device, against real PostgreSQL: admin-only as the rest of
 * device management (an ordinary client, an admin, a revoked admin), never for an admin device, and
 * only as long as the device that created the code stays an active admin; and whether a code it
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
  void anAdminDeviceCreatesAPairingForADeviceThatIsNotAnAdmin() throws SQLException {
    var caller = TestClients.registerAdmin("pairing-admin");

    var pairing =
        create(caller, "Tablet")
            .statusCode(201)
            .header("Location", nullValue())
            .body("name", equalTo("Tablet"))
            .body("admin", equalTo(false))
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
            .body("client.admin", equalTo(false))
            .extract();
    asClient(issued.path("clientKey")).get(CLIENT).then().statusCode(200);
    redeem(code).statusCode(401);
  }

  @Test
  void aClientThatIsNotAnAdminIsRefused() throws SQLException {
    var caller = TestClients.register("ordinary-pairing-caller");

    create(caller, "Refused " + caller.id())
        .statusCode(403)
        .body("title", equalTo("Not an admin device"))
        .body("status", equalTo(403))
        .body("violations.size()", equalTo(0));

    assertEquals(0, pairingsFor("Refused " + caller.id()));
  }

  @Test
  void aDeviceWhoseAdminRightsWereTakenAwayIsRefused() {
    var caller = TestClients.registerAdmin("former-pairing-admin");
    setAdmin(caller, false);

    create(caller, "Refused").statusCode(403).body("title", equalTo("Not an admin device"));
  }

  @Test
  void aRevokedAdminIsNotAuthenticated() throws SQLException {
    var caller = TestClients.registerAdmin("revoked-pairing-admin");
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
        // An admin device cannot pair an admin device, nor say it does not.
        "{\"name\": \"x\", \"admin\": true}",
        "{\"name\": \"x\", \"admin\": false}",
      })
  void invalidPairingsAreRejected(String body) {
    var caller = TestClients.registerAdmin("admin-with-invalid-pairing");

    asClient(caller.clientKey())
        .contentType(ContentType.JSON)
        .body(body)
        .post(PAIRINGS)
        .then()
        .statusCode(400);
  }

  @Test
  void aNameOfMoreThan100CharactersIsRejected() {
    var caller = TestClients.registerAdmin("admin-with-long-name");

    create(caller, "x".repeat(101)).statusCode(400);
    create(caller, "x".repeat(100)).statusCode(201);
  }

  @Test
  void theCodeStopsWorkingOnceItsDeviceIsRevoked() throws SQLException {
    var caller = TestClients.registerAdmin("stolen-admin");
    String code = create(caller, "Stolen code").statusCode(201).extract().path("code");

    asAdmin().post(ADMIN + "/" + caller.id() + "/revoke").then().statusCode(200);

    redeem(code).statusCode(401).body("title", equalTo("Unauthorized"));
    assertEquals(0, clientsNamed("Stolen code"));
    // Deleted, since it can never redeem again.
    assertEquals(0, pairingsFor("Stolen code"));
  }

  @Test
  void theCodeStopsWorkingOnceItsDeviceIsNoLongerAnAdmin() throws SQLException {
    var caller = TestClients.registerAdmin("demoted-admin");
    String code = create(caller, "Demoted code").statusCode(201).extract().path("code");

    setAdmin(caller, false);

    redeem(code).statusCode(401);
    assertEquals(0, clientsNamed("Demoted code"));
    // Made an admin again, the old code still does not come back.
    setAdmin(caller, true);
    redeem(code).statusCode(401);
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
    var caller = TestClients.registerAdmin("pairing-watcher");
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
    var caller = TestClients.registerAdmin("expired-pairing-watcher");
    var pairing = create(caller, "Late tablet").statusCode(201).extract();
    expire(pairing.path("code"));

    status(caller, pairing.path("id")).statusCode(200).body("state", equalTo("EXPIRED"));
  }

  @Test
  void anotherDevicesCodeIsUnknown() {
    var creator = TestClients.registerAdmin("pairing-owner");
    var other = TestClients.registerAdmin("pairing-snoop");
    String id = create(creator, "Someone else's").statusCode(201).extract().path("id");

    status(other, id).statusCode(404).body("title", equalTo("Not found"));
    status(other, UUID.randomUUID().toString()).statusCode(404).body("title", equalTo("Not found"));
    status(creator, id).statusCode(200);
  }

  @Test
  void theOperatorsCodeIsUnknownToADevice() {
    var caller = TestClients.registerAdmin("operator-pairing-snoop");
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
  void onlyAnActiveAdminDeviceAsks() {
    var creator = TestClients.registerAdmin("pairing-status-admin");
    String id = create(creator, "Asked about").statusCode(201).extract().path("id");
    var ordinary = TestClients.register("ordinary-pairing-status-caller");

    // Refused before the pairing is looked up: the same for a known and an unknown ID.
    status(ordinary, id).statusCode(403).body("title", equalTo("Not an admin device"));
    status(ordinary, UUID.randomUUID().toString())
        .statusCode(403)
        .body("title", equalTo("Not an admin device"));
    given().get(PAIRINGS + "/" + id).then().statusCode(401);
    asAdmin().get(PAIRINGS + "/" + id).then().statusCode(401);

    setAdmin(creator, false);
    status(creator, id).statusCode(403);
    setAdmin(creator, true);
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

  private static void setAdmin(Registered client, boolean admin) {
    asAdmin()
        .contentType(ContentType.JSON)
        .body(Map.of("admin", admin))
        .patch(ADMIN + "/" + client.id())
        .then()
        .statusCode(200);
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
