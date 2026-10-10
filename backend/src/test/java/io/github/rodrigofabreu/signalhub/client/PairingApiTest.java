package io.github.rodrigofabreu.signalhub.client;

import static io.github.rodrigofabreu.signalhub.TestClients.ADMIN;
import static io.github.rodrigofabreu.signalhub.TestClients.CLIENT;
import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.github.rodrigofabreu.signalhub.TestProducers.asProducer;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.endsWith;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.not;
import static org.hamcrest.Matchers.notNullValue;
import static org.hamcrest.Matchers.nullValue;
import static org.hamcrest.Matchers.startsWith;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.agroal.api.AgroalDataSource;
import io.github.rodrigofabreu.signalhub.TestClients;
import io.github.rodrigofabreu.signalhub.TestProducers;
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
import java.time.Instant;
import java.util.ArrayList;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/** Pairing a device: creating a pairing and redeeming its code, against real PostgreSQL. */
@QuarkusTest
class PairingApiTest {

  static final String PAIRINGS = "/api/v1/admin/pairings";
  static final String PAIRING = "/api/v1/pairing";

  @Inject AgroalDataSource dataSource;
  @Inject DeviceNotifier notifier;

  // Each redemption pushes a notice to the clients other tests gave push targets; it must be sent
  // before those tests count their pushes.
  @AfterEach
  void awaitNotices() throws Exception {
    notifier.awaitSent(Duration.ofSeconds(10));
  }

  @Test
  void aPairingHasAOneTimeCodeAndAUriWithThePublicUrl() {
    var before = Instant.now();
    var pairing =
        createPairing("Pixel 8")
            .body("name", equalTo("Pixel 8"))
            // With no user named, the owner's: an admin, so the device is an admin device.
            .body("admin", equalTo(true))
            .body("user.role", equalTo("ADMIN"))
            .body("code", startsWith(PairingCodes.PREFIX))
            .body("id", notNullValue())
            .header("Location", nullValue())
            .extract();
    String code = pairing.path("code");
    var expiresAt = Instant.parse(pairing.path("expiresAt"));

    assertEquals(
        "signalhub://pair?server="
            + URLEncoder.encode("https://signalhub.example.test", StandardCharsets.UTF_8)
            + "&code="
            + code,
        pairing.path("uri"));
    assertTrue(
        !expiresAt.isBefore(before.plus(PairingService.LIFETIME).minusSeconds(1))
            && !expiresAt.isAfter(Instant.now().plus(PairingService.LIFETIME)),
        "expires in 10 minutes: " + expiresAt);
  }

  @Test
  void redeemingRegistersTheClientOnce() {
    String code = createPairing("Paired phone").extract().path("code");

    var issued =
        redeem(code)
            .statusCode(201)
            .header("Location", endsWith(CLIENT))
            .body("client.name", equalTo("Paired phone"))
            .body("client.admin", equalTo(true))
            .body("client.revokedAt", nullValue())
            .body("clientKey", startsWith("shck1_"))
            .extract();
    String clientKey = issued.path("clientKey");
    String id = issued.path("client.id");

    asClient(clientKey).get(CLIENT).then().statusCode(200).body("id", equalTo(id));
    asAdmin().get(ADMIN).then().body("items.id", hasItem(id));
    redeem(code).statusCode(401).body("title", equalTo("Unauthorized"));
  }

  @Test
  void aPairingIsForAUserAndTheDeviceIsAnAdminDeviceWhenTheUserIsAnAdmin() {
    for (var role : new String[] {"BASIC", "MOD", "ADMIN"}) {
      var user = TestUsers.create("pairing-" + role, role);
      String code =
          asAdmin()
              .contentType(ContentType.JSON)
              .body(Map.of("name", role + " phone", "userId", user.id().toString()))
              .post(PAIRINGS)
              .then()
              .statusCode(201)
              .body("admin", equalTo(role.equals("ADMIN")))
              .body("user.id", equalTo(user.id().toString()))
              .extract()
              .path("code");

      var issued =
          redeem(code)
              .statusCode(201)
              .body("client.admin", equalTo(role.equals("ADMIN")))
              .body("client.user.id", equalTo(user.id().toString()))
              .body("client.user.role", equalTo(role))
              .extract();

      asClient(issued.path("clientKey"))
          .get(CLIENT)
          .then()
          .body("admin", equalTo(role.equals("ADMIN")))
          .body("user.name", equalTo(user.name()));
    }
  }

  @Test
  void anAdminDeviceCannotBeAskedForAUserWhoIsNotAnAdmin() {
    var user = TestUsers.create("pairing-not-admin", "MOD");

    asAdmin()
        .contentType(ContentType.JSON)
        .body(Map.of("name", "Phone", "userId", user.id().toString(), "admin", true))
        .post(PAIRINGS)
        .then()
        .statusCode(409)
        .body("title", equalTo("Roles are set per user, not per device"));
    // Said by the flag that can only be true for an admin's device, false is just what it is.
    asAdmin()
        .contentType(ContentType.JSON)
        .body(Map.of("name", "Phone", "userId", user.id().toString(), "admin", false))
        .post(PAIRINGS)
        .then()
        .statusCode(201);
  }

  @Test
  void aPairingNeedsAnActiveUser() {
    var user = TestUsers.create("pairing-revoked", "BASIC");
    asAdmin().post(TestUsers.ADMIN + "/" + user.id() + "/revoke").then().statusCode(200);

    asAdmin()
        .contentType(ContentType.JSON)
        .body(Map.of("name", "Phone", "userId", user.id().toString()))
        .post(PAIRINGS)
        .then()
        .statusCode(409)
        .body("title", equalTo("User is revoked"));
    asAdmin()
        .contentType(ContentType.JSON)
        .body(Map.of("name", "Phone", "userId", UUID.randomUUID().toString()))
        .post(PAIRINGS)
        .then()
        .statusCode(404);
  }

  @Test
  void aPairedClientIsRevokedLikeAnyOther() {
    String code = createPairing("Revoked phone").extract().path("code");
    var issued = redeem(code).statusCode(201).extract();
    String clientKey = issued.path("clientKey");

    asAdmin().post(ADMIN + "/" + issued.path("client.id") + "/revoke").then().statusCode(200);

    asClient(clientKey).get(CLIENT).then().statusCode(401);
  }

  @Test
  void anExpiredCodeDoesNotRedeem() throws SQLException {
    String code = createPairing("Late phone").extract().path("code");
    expire(code);

    redeem(code).statusCode(401);
  }

  @Test
  void aPairingIsPendingUntilItsCodeIsUsed() {
    var pairing = createPairing("Waiting phone").extract();
    String id = pairing.path("id");

    status(id)
        .statusCode(200)
        .body("id", equalTo(id))
        .body("state", equalTo("PENDING"))
        .body("expiresAt", equalTo(pairing.path("expiresAt")))
        .body("redeemedAt", nullValue())
        .body("client", nullValue());
  }

  @Test
  void aUsedPairingNamesTheDeviceThatRedeemedIt() {
    var pairing = createPairing("Used phone").extract();
    String id = pairing.path("id");
    String code = pairing.path("code");
    String clientId = redeem(code).statusCode(201).extract().path("client.id");

    var status =
        status(id)
            .statusCode(200)
            .body("state", equalTo("REDEEMED"))
            .body("client.id", equalTo(clientId))
            .body("client.name", equalTo("Used phone"))
            .body("redeemedAt", notNullValue())
            .extract();

    // Neither the code nor a key, ever.
    assertEquals(Map.of("id", clientId, "name", "Used phone"), status.path("client"));
    assertFalse(status.asString().contains(code.substring(6)));
    assertFalse(status.asString().contains("shck1_"));
  }

  @Test
  void aUsedCodeNeverRedeemsAgain() throws SQLException {
    var pairing = createPairing("Once phone").extract();
    String code = pairing.path("code");
    redeem(code).statusCode(201);

    redeem(code).statusCode(401).body("title", equalTo("Unauthorized"));

    // Kept, marked as used, so its status can still be read.
    assertEquals(1, pairingsWith(code));
    assertEquals(1, clientsNamed("Once phone"));
    status(pairing.path("id")).body("state", equalTo("REDEEMED"));
  }

  @Test
  void aUsedPairingNamesTheDeviceAsItIsNamedNow() {
    var pairing = createPairing("Before rename").extract();
    String clientId = redeem(pairing.path("code")).statusCode(201).extract().path("client.id");
    asAdmin()
        .contentType(ContentType.JSON)
        .body(Map.of("name", "After rename"))
        .patch(ADMIN + "/" + clientId)
        .then()
        .statusCode(200);

    status(pairing.path("id")).body("client.name", equalTo("After rename"));
  }

  @Test
  void aPairingWhoseDeviceWasDeletedIsUnknown() {
    var pairing = createPairing("Deleted phone").extract();
    String clientId = redeem(pairing.path("code")).statusCode(201).extract().path("client.id");
    asAdmin().post(ADMIN + "/" + clientId + "/revoke").then().statusCode(200);
    asAdmin().delete(ADMIN + "/" + clientId).then().statusCode(204);

    status(pairing.path("id")).statusCode(404);
  }

  @Test
  void anExpiredPairingSaysSo() throws SQLException {
    var pairing = createPairing("Expired phone").extract();
    expire(pairing.path("code"));

    status(pairing.path("id")).statusCode(200).body("state", equalTo("EXPIRED"));
  }

  @Test
  void anUnknownPairingIsNotFound() {
    status(UUID.randomUUID().toString())
        .statusCode(404)
        .body("title", equalTo("Not found"))
        .body("status", equalTo(404));
    status("not-a-uuid").statusCode(404);
  }

  @Test
  void anAdminDevicesPairingIsUnknownToTheAdminToken() {
    var admin = TestClients.registerAs("ADMIN", "device-with-pairing");
    String id =
        asClient(admin.clientKey())
            .contentType(ContentType.JSON)
            .body(Map.of("name", "Device's code"))
            .post(CLIENT + "/pairings")
            .then()
            .statusCode(201)
            .extract()
            .path("id");

    status(id).statusCode(404);
  }

  @Test
  void aPairingsStatusNeedsTheAdminToken() {
    String id = createPairing("Private phone").extract().path("id");
    var client = TestClients.register("pairing-status-caller");

    given().get(PAIRINGS + "/" + id).then().statusCode(401);
    asClient(client.clientKey()).get(PAIRINGS + "/" + id).then().statusCode(401);
  }

  @Test
  void creatingAPairingKeepsRecentlyExpiredOnes() throws SQLException {
    var pairing = createPairing("Just expired phone").extract();
    expire(pairing.path("code"));

    createPairing("Next phone");

    status(pairing.path("id")).statusCode(200).body("state", equalTo("EXPIRED"));
  }

  @Test
  void creatingAPairingDeletesThoseExpiredLongerAgo() throws SQLException {
    var forgotten = createPairing("Forgotten phone").extract();
    var used = createPairing("Long used phone").extract();
    String usedClient = redeem(used.path("code")).statusCode(201).extract().path("client.id");
    var longAgo = PairingService.LIFETIME.plus(PairingService.KEPT_AFTER_EXPIRY).plusMinutes(1);
    expire(forgotten.path("code"), longAgo);
    expire(used.path("code"), longAgo);

    createPairing("Next phone");

    assertEquals(0, pairingsWith(forgotten.path("code")));
    assertEquals(0, pairingsWith(used.path("code")));
    status(forgotten.path("id")).statusCode(404);
    status(used.path("id")).statusCode(404);
    // The client it made stays.
    asAdmin().get(ADMIN + "/" + usedClient).then().statusCode(200);
  }

  @Test
  void concurrentRedemptionsMakeOneClient() throws Exception {
    String code = createPairing("Raced phone").extract().path("code");
    var requests = 8;
    var statuses = new ArrayList<Integer>();
    try (var pool = Executors.newFixedThreadPool(requests)) {
      var answers = new ArrayList<Future<ValidatableResponse>>();
      for (var i = 0; i < requests; i++) {
        Callable<ValidatableResponse> send = () -> redeem(code);
        answers.add(pool.submit(send));
      }
      for (var answer : answers) {
        statuses.add(answer.get().extract().statusCode());
      }
    }

    assertEquals(1, statuses.stream().filter(status -> status == 201).count());
    assertEquals(requests - 1, statuses.stream().filter(status -> status == 401).count());
    assertEquals(1, clientsNamed("Raced phone"));
  }

  @Test
  void onlyTheHashOfTheCodeIsStored() throws SQLException {
    String code = createPairing("Hashed phone").extract().path("code");
    try (var connection = dataSource.getConnection();
        var statement =
            connection.prepareStatement(
                "SELECT pairings::text FROM pairings WHERE code_hash = ? AND client_name = ?")) {
      statement.setBytes(1, ApiKeys.hash(code));
      statement.setString(2, "Hashed phone");
      try (var row = statement.executeQuery()) {
        assertTrue(row.next());
        assertFalse(row.getString(1).contains(code.substring(6)), "the secret is not stored");
      }
    }
  }

  @ParameterizedTest
  @ValueSource(
      strings = {
        "",
        "Bearer ",
        "Bearer shpc1_AAAAAAAAAAAAAAAAAAAAAA",
        "Bearer shpc1_short",
        "Basic c2hwYzFf",
      })
  void unknownOrMalformedCodesAreRejected(String authorization) {
    var request = given();
    if (!authorization.isEmpty()) {
      request = request.header("Authorization", authorization);
    }
    request
        .post(PAIRING)
        .then()
        .statusCode(401)
        .header("WWW-Authenticate", containsString("Bearer"))
        .body("title", equalTo("Unauthorized"));
  }

  @Test
  void otherCredentialsDoNotRedeem() {
    var client = TestClients.register("not-a-code");
    var producer = TestProducers.register("pairing-producer");
    asClient(client.clientKey()).post(PAIRING).then().statusCode(401);
    asProducer(producer.apiKey()).post(PAIRING).then().statusCode(401);
    asAdmin().post(PAIRING).then().statusCode(401);
  }

  @Test
  void creatingAPairingRequiresTheAdminToken() {
    var client = TestClients.register("pairing-mgmt");
    given()
        .contentType(ContentType.JSON)
        .body("{\"name\": \"x\"}")
        .post(PAIRINGS)
        .then()
        .statusCode(401);
    asClient(client.clientKey())
        .contentType(ContentType.JSON)
        .body("{\"name\": \"x\"}")
        .post(PAIRINGS)
        .then()
        .statusCode(401);
  }

  @ParameterizedTest
  @ValueSource(strings = {"{}", "{\"name\": \" \"}", "{\"name\": \"a\\u0000b\"}", "{\"x\": 1}"})
  void invalidPairingsAreRejected(String body) {
    asAdmin().contentType(ContentType.JSON).body(body).post(PAIRINGS).then().statusCode(400);
  }

  @Test
  void theCodeIsNeverInAnotherResponse() {
    String code = createPairing("Quiet phone").extract().path("code");
    asAdmin().get(ADMIN).then().body(not(containsString(code)));
  }

  private static ValidatableResponse createPairing(String name) {
    return asAdmin()
        .contentType(ContentType.JSON)
        .body("{\"name\": \"" + name + "\"}")
        .post(PAIRINGS)
        .then()
        .statusCode(201);
  }

  private static ValidatableResponse redeem(String code) {
    return given().header("Authorization", "Bearer " + code).post(PAIRING).then();
  }

  private static ValidatableResponse status(String id) {
    return asAdmin().get(PAIRINGS + "/" + id).then();
  }

  // Just expired: 11 minutes old.
  private void expire(String code) throws SQLException {
    expire(code, Duration.ofMinutes(11));
  }

  private void expire(String code, Duration age) throws SQLException {
    try (var connection = dataSource.getConnection();
        var statement =
            connection.prepareStatement(
                "UPDATE pairings SET created_at = created_at - ?::interval,"
                    + " expires_at = expires_at - ?::interval WHERE code_hash = ?")) {
      var shift = age.toSeconds() + " seconds";
      statement.setString(1, shift);
      statement.setString(2, shift);
      statement.setBytes(3, ApiKeys.hash(code));
      assertEquals(1, statement.executeUpdate());
    }
  }

  private long pairingsWith(String code) throws SQLException {
    return count("SELECT count(*) FROM pairings WHERE code_hash = ?", ApiKeys.hash(code));
  }

  private long clientsNamed(String name) throws SQLException {
    return count("SELECT count(*) FROM clients WHERE name = ?", name);
  }

  private long count(String query, Object parameter) throws SQLException {
    try (var connection = dataSource.getConnection();
        var statement = connection.prepareStatement(query)) {
      statement.setObject(1, parameter);
      try (var row = statement.executeQuery()) {
        row.next();
        return row.getLong(1);
      }
    }
  }
}
