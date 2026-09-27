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
import static org.hamcrest.Matchers.nullValue;
import static org.hamcrest.Matchers.startsWith;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.agroal.api.AgroalDataSource;
import io.github.rodrigofabreu.signalhub.TestClients;
import io.github.rodrigofabreu.signalhub.TestProducers;
import io.github.rodrigofabreu.signalhub.producer.ApiKeys;
import io.github.rodrigofabreu.signalhub.push.PairingNotifier;
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
  @Inject PairingNotifier notifier;

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
            .body("code", startsWith(PairingCodes.PREFIX))
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
  void creatingAPairingDeletesExpiredOnes() throws SQLException {
    String code = createPairing("Forgotten phone").extract().path("code");
    expire(code);

    createPairing("Next phone");

    assertEquals(0, pairingsWith(code));
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

  private void expire(String code) throws SQLException {
    try (var connection = dataSource.getConnection();
        var statement =
            connection.prepareStatement(
                "UPDATE pairings SET created_at = created_at - ?::interval,"
                    + " expires_at = expires_at - ?::interval WHERE code_hash = ?")) {
      var shift = Duration.ofMinutes(11).toSeconds() + " seconds";
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
