package io.github.rodrigofabreu.signalhub.client;

import static io.github.rodrigofabreu.signalhub.TestClients.ADMIN;
import static io.github.rodrigofabreu.signalhub.TestClients.CLIENT;
import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.github.rodrigofabreu.signalhub.TestProducers.asProducer;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.notNullValue;
import static org.hamcrest.Matchers.nullValue;
import static org.junit.jupiter.api.Assertions.assertEquals;

import io.agroal.api.AgroalDataSource;
import io.github.rodrigofabreu.signalhub.TestClients;
import io.github.rodrigofabreu.signalhub.TestClients.Registered;
import io.github.rodrigofabreu.signalhub.TestProducers;
import io.github.rodrigofabreu.signalhub.TestUsers;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import io.restassured.response.ValidatableResponse;
import jakarta.inject.Inject;
import java.sql.SQLException;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;

/**
 * Deleting revoked clients, with the admin token and from a device as its user's role allows,
 * against real PostgreSQL: an active client is refused and unchanged, a revoked one goes with
 * everything that exists only for it, and events stay.
 */
@QuarkusTest
class ClientDeletionApiTest {

  private static final String DEVICES = CLIENT + "/devices";

  @Inject AgroalDataSource dataSource;

  /** The client a request is about, relative to the caller. */
  enum Target {
    ORDINARY,
    ADMINS,
    ITSELF,
    REVOKED,
    REVOKED_ADMIN,
    UNKNOWN
  }

  @Test
  void theOperatorCannotDeleteAnActiveClient() {
    var client = TestClients.register("active-not-deleted");
    var before = asAdmin().get(ADMIN + "/" + client.id()).then().extract().asString();

    deleteAsOperator(client.id())
        .statusCode(409)
        .body("title", equalTo("Client is not revoked"))
        .body("status", equalTo(409));

    assertEquals(before, asAdmin().get(ADMIN + "/" + client.id()).then().extract().asString());
    asClient(client.clientKey()).get(CLIENT).then().statusCode(200);
  }

  @Test
  void theOperatorDeletesARevokedClientWithItsDataButNotItsEvents() throws SQLException {
    var client = TestClients.register("deleted-by-operator");
    var eventId = clientWithData(client);
    revoke(client.id());

    deleteAsOperator(client.id()).statusCode(204);

    assertGoneWithItsData(client.id(), eventId);
  }

  @Test
  void theOperatorDeletesARevokedAdminWithTheUnusedPairingCodesItCreated() throws SQLException {
    var admin = TestClients.registerAs("ADMIN", "revoked-admin-deleted-by-operator");
    var eventId = clientWithData(admin);
    createPairing(admin);
    revoke(admin.id());

    deleteAsOperator(admin.id()).statusCode(204);

    assertGoneWithItsData(admin.id(), eventId);
  }

  @Test
  void theOperatorDeletesOnce() {
    var client = TestClients.register("deleted-twice");
    revoke(client.id());

    deleteAsOperator(client.id()).statusCode(204);
    deleteAsOperator(client.id()).statusCode(404).body("status", equalTo(404));
  }

  @Test
  void theOperatorGetsNotFoundForAnUnknownClient() {
    deleteAsOperator(UUID.randomUUID())
        .statusCode(404)
        .body("title", equalTo("Not found"))
        .body("status", equalTo(404));
  }

  @Test
  void deletingNeedsTheAdminToken() {
    var client = TestClients.register("delete-needs-token");
    revoke(client.id());

    given().delete(ADMIN + "/" + client.id()).then().statusCode(401);
    given()
        .header("Authorization", "Bearer " + client.clientKey())
        .delete(ADMIN + "/" + client.id())
        .then()
        .statusCode(401);
    asAdmin().get(ADMIN + "/" + client.id()).then().statusCode(200);
  }

  @ParameterizedTest
  @EnumSource(Target.class)
  void aBasicUserIsRefusedWhateverTheTarget(Target target) {
    var caller = TestClients.registerAs("BASIC", "basic-deleting");
    var id = target(target, caller);

    deleteAsDevice(caller, id)
        .statusCode(403)
        .body("title", equalTo("Not allowed for your role"))
        .body("status", equalTo(403));

    if (target != Target.UNKNOWN) {
      asAdmin().get(ADMIN + "/" + id).then().statusCode(200);
    }
  }

  @ParameterizedTest
  @EnumSource(Target.class)
  void aRevokedAdminIsNotAuthenticatedWhateverTheTarget(Target target) {
    var caller = TestClients.registerAs("ADMIN", "revoked-admin-deleting");
    var id = target(target, caller);
    revoke(caller.id());

    deleteAsDevice(caller, id).statusCode(401);

    asAdmin().get(ADMIN + "/" + caller.id()).then().statusCode(200);
  }

  @ParameterizedTest
  @EnumSource(
      value = Target.class,
      names = {"ORDINARY", "ADMINS", "ITSELF"})
  void anAdminCannotDeleteAnActiveDevice(Target target) {
    var caller = TestClients.registerAs("ADMIN", "admin-deleting-active");
    var id = target(target, caller);

    // An admin's device (its own too) is the operator's to deal with; any other must be revoked.
    deleteAsDevice(caller, id)
        .statusCode(409)
        .body(
            "title",
            equalTo(
                target == Target.ORDINARY ? "Client is not revoked" : "Client is an admin device"))
        .body("status", equalTo(409));

    asAdmin().get(ADMIN + "/" + id).then().statusCode(200).body("revokedAt", nullValue());
  }

  @Test
  void anAdminDeletesARevokedDeviceWithItsDataButNotItsEvents() throws SQLException {
    var caller = TestClients.registerAs("ADMIN", "admin-deleting");
    var client = TestClients.register("deleted-by-admin");
    var user = TestClients.registerAs("MOD", "deleted-by-admin-mod");
    var eventId = clientWithData(client);
    revoke(user.id());

    deleteAsDevice(caller, user.id()).statusCode(204);

    asAdmin().get(ADMIN + "/" + user.id()).then().statusCode(404);
    assertEquals(0, count("SELECT count(*) FROM clients WHERE id = ?", user.id()));
    asAdmin().get("/api/v1/events/" + eventId).then().statusCode(200);
    asClient(caller.clientKey()).get(DEVICES).then().statusCode(200);
  }

  @Test
  void anAdminCannotDeleteARevokedAdminsDevice() {
    var caller = TestClients.registerAs("ADMIN", "admin-deleting-admin");
    var other = TestClients.registerAs("ADMIN", "revoked-admin-deleted-by-admin");
    revoke(other.id());

    deleteAsDevice(caller, other.id())
        .statusCode(409)
        .body("title", equalTo("Client is an admin device"));

    asAdmin().get(ADMIN + "/" + other.id()).then().statusCode(200);
  }

  @Test
  void aModDeletesTheirOwnRevokedDevicesOnly() {
    var caller = TestClients.registerAs("MOD", "mod-deleting");
    var own = TestClients.registerFor(caller.userId(), "mod-own-revoked");
    var other = TestClients.registerAs("MOD", "someone-elses-revoked");
    revoke(own.id());
    revoke(other.id());

    deleteAsDevice(caller, other.id()).statusCode(404).body("title", equalTo("Not found"));
    asAdmin().get(ADMIN + "/" + other.id()).then().statusCode(200);
    // An own device that is still active must be revoked first.
    deleteAsDevice(caller, caller.id())
        .statusCode(409)
        .body("title", equalTo("Client is not revoked"));
    deleteAsDevice(caller, own.id()).statusCode(204);
    asAdmin().get(ADMIN + "/" + own.id()).then().statusCode(404);
  }

  @Test
  void anAdminDeletesOnceAndGetsNotFoundForAnUnknownDevice() {
    var caller = TestClients.registerAs("ADMIN", "admin-deleting-twice");
    var client = TestClients.registerAs("MOD", "deleted-twice-by-admin");
    revoke(client.id());

    deleteAsDevice(caller, client.id()).statusCode(204);
    deleteAsDevice(caller, client.id())
        .statusCode(404)
        .body("title", equalTo("Not found"))
        .body("status", equalTo(404));
    deleteAsDevice(caller, UUID.randomUUID()).statusCode(404);
    deleteAsDevice(caller, "not-a-uuid").statusCode(404);
  }

  @Test
  void deletingADeviceNeedsAClientKey() {
    var client = TestClients.register("device-delete-needs-key");
    revoke(client.id());

    given().delete(DEVICES + "/" + client.id()).then().statusCode(401);
    // The admin token is not a client key: the operator has the management API.
    asAdmin().delete(DEVICES + "/" + client.id()).then().statusCode(401);
    asAdmin().get(ADMIN + "/" + client.id()).then().statusCode(200);
  }

  @Test
  void everyTableThatReferencesClientsLosesItsRowsWithTheClient() throws SQLException {
    // A later table that forgets ON DELETE CASCADE would make deleting a client fail.
    try (var connection = dataSource.getConnection();
        var statement =
            connection.prepareStatement(
                "SELECT count(*) FROM pg_constraint WHERE contype = 'f'"
                    + " AND confrelid = 'clients'::regclass AND confdeltype <> 'c'");
        var rows = statement.executeQuery()) {
      rows.next();
      assertEquals(0, rows.getLong(1));
    }
  }

  /**
   * Gives the client an event it marked read, push results, a pending retry and a delivery record;
   * returns the event.
   */
  private UUID clientWithData(Registered client) throws SQLException {
    // Public, so that the client's user, whoever it is, can be subscribed and read its events.
    var producer = TestProducers.registerPublic("deletion");
    TestUsers.subscribe(client.userId(), producer.id());
    var eventId =
        UUID.fromString(
            asProducer(producer.apiKey())
                .contentType(ContentType.JSON)
                .body(Map.of("category", "INFO", "severity", "LOW", "title", "Kept"))
                .post("/api/v1/events")
                .then()
                .statusCode(201)
                .extract()
                .path("id"));
    asClient(client.clientKey()).put("/api/v1/events/" + eventId + "/read").then().statusCode(200);
    execute(
        "UPDATE clients SET last_push_succeeded_at = now(), last_push_succeeded_event_id = ?,"
            + " last_push_failed_at = now(), last_push_failed_event_id = ?,"
            + " last_push_failed_result = 'TRANSIENT_FAILURE' WHERE id = ?",
        eventId,
        eventId,
        client.id());
    execute(
        "INSERT INTO push_retries (event_id, client_id, attempts, next_attempt_at)"
            + " VALUES (?, ?, 1, now() + interval '1 hour')",
        eventId,
        client.id());
    execute(
        "INSERT INTO event_deliveries (event_id, client_id, attempt, outcome, detail, at)"
            + " VALUES (?, ?, 1, 'TRANSIENT_FAILURE', 'HTTP 503', now())",
        eventId,
        client.id());
    asAdmin()
        .get(ADMIN + "/" + client.id())
        .then()
        .body("pushStatus.lastSuccess", notNullValue())
        .body("pushStatus.pendingRetries", equalTo(1));
    return eventId;
  }

  private void createPairing(Registered admin) throws SQLException {
    asClient(admin.clientKey())
        .contentType(ContentType.JSON)
        .body("{\"name\": \"from " + admin.id() + "\"}")
        .post(CLIENT + "/pairings")
        .then()
        .statusCode(201);
    assertEquals(1, count("SELECT count(*) FROM pairings WHERE created_by = ?", admin.id()));
  }

  private void assertGoneWithItsData(UUID id, UUID eventId) throws SQLException {
    asAdmin().get(ADMIN + "/" + id).then().statusCode(404);
    asAdmin().get(ADMIN).then().body("items.find { it.id == '" + id + "' }", nullValue());
    assertEquals(0, count("SELECT count(*) FROM clients WHERE id = ?", id));
    assertEquals(0, count("SELECT count(*) FROM push_retries WHERE client_id = ?", id));
    assertEquals(0, count("SELECT count(*) FROM event_deliveries WHERE client_id = ?", id));
    assertEquals(0, count("SELECT count(*) FROM pairings WHERE created_by = ?", id));
    // The event is its producer's and its user's, not the client's: it stays, still read by the
    // user.
    asAdmin().get("/api/v1/events/" + eventId).then().statusCode(200);
    assertEquals(1, count("SELECT count(*) FROM event_reads WHERE event_id = ?", eventId));
  }

  private static UUID target(Target target, Registered caller) {
    return switch (target) {
      case ORDINARY -> TestClients.registerAs("MOD", "ordinary-target").id();
      case ADMINS -> TestClients.registerAs("ADMIN", "admin-target").id();
      case ITSELF -> caller.id();
      case REVOKED -> revoke(TestClients.registerAs("MOD", "revoked-target").id());
      case REVOKED_ADMIN -> revoke(TestClients.registerAs("ADMIN", "revoked-admin-target").id());
      case UNKNOWN -> UUID.randomUUID();
    };
  }

  private static UUID revoke(UUID id) {
    asAdmin().post(ADMIN + "/" + id + "/revoke").then().statusCode(200);
    return id;
  }

  private static ValidatableResponse deleteAsOperator(UUID id) {
    return asAdmin().delete(ADMIN + "/" + id).then();
  }

  private static ValidatableResponse deleteAsDevice(Registered caller, Object id) {
    return asClient(caller.clientKey()).delete(DEVICES + "/" + id).then();
  }

  private void execute(String sql, Object... parameters) throws SQLException {
    try (var connection = dataSource.getConnection();
        var statement = connection.prepareStatement(sql)) {
      for (var i = 0; i < parameters.length; i++) {
        statement.setObject(i + 1, parameters[i]);
      }
      statement.executeUpdate();
    }
  }

  private long count(String sql, UUID id) throws SQLException {
    try (var connection = dataSource.getConnection();
        var statement = connection.prepareStatement(sql)) {
      statement.setObject(1, id);
      try (var rows = statement.executeQuery()) {
        rows.next();
        return rows.getLong(1);
      }
    }
  }
}
