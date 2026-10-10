package io.github.rodrigofabreu.signalhub;

import static io.github.rodrigofabreu.signalhub.TestClients.CLIENT;
import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.github.rodrigofabreu.signalhub.TestProducers.asProducer;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.notNullValue;
import static org.hamcrest.Matchers.nullValue;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.agroal.api.AgroalDataSource;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import jakarta.inject.Inject;
import java.sql.SQLException;
import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;

/**
 * When a client last made a request and a producer key last published, recorded at most once a
 * minute and served where the caller may already see the client or the key, against real
 * PostgreSQL.
 */
@QuarkusTest
class LastUsedApiTest {

  @Inject AgroalDataSource dataSource;

  @Test
  void aClientIsNeverActiveUntilItsFirstRequest() {
    var client = TestClients.register("never-active");

    asAdmin()
        .get("/api/v1/admin/clients/" + client.id())
        .then()
        .statusCode(200)
        .body("lastActiveAt", nullValue());
    assertEquals(null, stored("clients", "last_active_at", client.id()));
  }

  @Test
  void aRequestRecordsWhenTheClientWasActive() throws SQLException {
    var client = TestClients.register("active");
    var before = Instant.now().minusSeconds(1);

    asClient(client.clientKey()).get(CLIENT).then().statusCode(200);

    var recorded = stored("clients", "last_active_at", client.id());
    assertTrue(recorded.isAfter(before) && !recorded.isAfter(Instant.now()));
    asAdmin()
        .get("/api/v1/admin/clients/" + client.id())
        .then()
        .body("lastActiveAt", equalTo(recorded.toString()));
    asClient(client.clientKey())
        .get(CLIENT)
        .then()
        .body("lastActiveAt", equalTo(recorded.toString()));
  }

  @Test
  void aClientIsRecordedAtMostOnceAMinute() throws SQLException {
    var client = TestClients.register("throttled");
    asClient(client.clientKey()).get(CLIENT).then().statusCode(200);
    var first = stored("clients", "last_active_at", client.id());

    asClient(client.clientKey()).get(CLIENT).then().statusCode(200);
    assertEquals(first, stored("clients", "last_active_at", client.id()));

    // A time a minute old is replaced by the next request.
    set("clients", "last_active_at", client.id(), first.minus(Duration.ofMinutes(2)));
    asClient(client.clientKey()).get(CLIENT).then().statusCode(200);
    assertTrue(stored("clients", "last_active_at", client.id()).isAfter(first.minusSeconds(1)));
  }

  @Test
  void aRejectedKeyRecordsNothing() {
    var client = TestClients.register("rejected");
    var wrong = client.clientKey().substring(0, client.clientKey().length() - 1) + "x";

    asClient(wrong).get(CLIENT).then().statusCode(401);

    assertEquals(null, stored("clients", "last_active_at", client.id()));
  }

  @Test
  void eachRoleSeesLastActiveAtOnlyOnTheDevicesItMayList() {
    var mod = TestClients.registerAs("MOD", "mod-device");
    var modOther = TestClients.registerFor(mod.userId(), "mod-other");
    var basic = TestClients.registerAs("BASIC", "basic-device");
    var admin = TestClients.registerAdmin("admin-device");
    for (var device : new TestClients.Registered[] {mod, modOther, basic, admin}) {
      asClient(device.clientKey()).get(CLIENT).then().statusCode(200);
    }

    // A mod lists their own devices only, each with its time.
    asClient(mod.clientKey())
        .get(CLIENT + "/devices")
        .then()
        .statusCode(200)
        .body(
            "items.id",
            org.hamcrest.Matchers.containsInAnyOrder(mod.id().toString(), modOther.id().toString()))
        .body("items.find { it.id == '" + modOther.id() + "' }.lastActiveAt", notNullValue());
    // A basic user sees their own device's time and no one else's device.
    asClient(basic.clientKey())
        .get(CLIENT + "/devices")
        .then()
        .statusCode(200)
        .body("items.id", org.hamcrest.Matchers.contains(basic.id().toString()))
        .body("items[0].lastActiveAt", notNullValue());
    // An admin lists every device, with each time.
    asClient(admin.clientKey())
        .get(CLIENT + "/devices")
        .then()
        .statusCode(200)
        .body("items.find { it.id == '" + mod.id() + "' }.lastActiveAt", notNullValue())
        .body("items.find { it.id == '" + basic.id() + "' }.lastActiveAt", notNullValue());
  }

  @Test
  void aProducerKeyIsNeverUsedUntilItPublishes() {
    var producer = TestProducers.register("never-used");

    asAdmin()
        .get(TestProducers.ADMIN + "/" + producer.id())
        .then()
        .statusCode(200)
        .body("keys[0].lastUsedAt", nullValue());
    assertEquals(null, stored("producer_api_keys", "last_used_at", producer.keyId()));
  }

  @Test
  void aPublishRecordsWhenTheKeyWasUsedAndOnlyThatKey() {
    var producer = TestProducers.register("used");
    var secondKey =
        asAdmin()
            .post(TestProducers.ADMIN + "/" + producer.id() + "/keys")
            .then()
            .statusCode(201)
            .extract()
            .<String>path("keyId");

    publish(producer.apiKey());

    var recorded = stored("producer_api_keys", "last_used_at", producer.keyId());
    assertEquals(null, stored("producer_api_keys", "last_used_at", UUID.fromString(secondKey)));
    asAdmin()
        .get(TestProducers.ADMIN + "/" + producer.id())
        .then()
        .body(
            "keys.find { it.id == '" + producer.keyId() + "' }.lastUsedAt",
            equalTo(recorded.toString()))
        .body("keys.find { it.id == '" + secondKey + "' }.lastUsedAt", nullValue());
  }

  @Test
  void aProducerKeyIsRecordedAtMostOnceAMinute() {
    var producer = TestProducers.register("key-throttled");
    publish(producer.apiKey());
    var first = stored("producer_api_keys", "last_used_at", producer.keyId());

    publish(producer.apiKey());
    assertEquals(first, stored("producer_api_keys", "last_used_at", producer.keyId()));

    set("producer_api_keys", "last_used_at", producer.keyId(), first.minus(Duration.ofMinutes(2)));
    publish(producer.apiKey());
    assertNotEquals(
        first.minus(Duration.ofMinutes(2)),
        stored("producer_api_keys", "last_used_at", producer.keyId()));
  }

  @Test
  void aRevokedKeyKeepsItsLastUse() {
    var producer = TestProducers.register("revoked-key");
    publish(producer.apiKey());
    var recorded = stored("producer_api_keys", "last_used_at", producer.keyId());

    asAdmin()
        .post(TestProducers.ADMIN + "/" + producer.id() + "/keys/" + producer.keyId() + "/revoke")
        .then()
        .statusCode(200)
        .body("keys[0].lastUsedAt", equalTo(recorded.toString()));
    asProducer(producer.apiKey())
        .contentType(ContentType.JSON)
        .body(event())
        .post("/api/v1/events")
        .then()
        .statusCode(401);
    assertEquals(recorded, stored("producer_api_keys", "last_used_at", producer.keyId()));
  }

  @Test
  void anOwnerSeesWhenTheirKeysWereUsed() {
    var owner = TestClients.registerAs("BASIC", "key-viewer");
    var created =
        asClient(owner.clientKey())
            .contentType(ContentType.JSON)
            .body(Map.of("name", "own-" + UUID.randomUUID()))
            .post(CLIENT + "/producers")
            .then()
            .statusCode(201)
            .extract();
    var id = created.<String>path("producer.id");
    var key = created.<String>path("apiKey");

    asClient(owner.clientKey())
        .get(CLIENT + "/producers/" + id)
        .then()
        .body("keys[0].lastUsedAt", nullValue());
    publish(key);
    asClient(owner.clientKey())
        .get(CLIENT + "/producers/" + id)
        .then()
        .body("keys[0].lastUsedAt", notNullValue());
    asClient(owner.clientKey())
        .get(CLIENT + "/producers")
        .then()
        .body("items.find { it.id == '" + id + "' }.keys[0].lastUsedAt", notNullValue());
  }

  @Test
  void anyClientKeyReadsTheServersVersion() {
    var basic = TestClients.registerAs("BASIC", "about");

    asClient(basic.clientKey())
        .get(CLIENT + "/server")
        .then()
        .statusCode(200)
        .body("version", equalTo("development"))
        .body("commit", nullValue());
  }

  @Test
  void theServersVersionNeedsAClientKey() {
    io.restassured.RestAssured.given().get(CLIENT + "/server").then().statusCode(401);
  }

  private static Map<String, String> event() {
    return Map.of("category", "INFO", "severity", "LOW", "title", "t");
  }

  private static void publish(String apiKey) {
    asProducer(apiKey)
        .contentType(ContentType.JSON)
        .body(event())
        .post("/api/v1/events")
        .then()
        .statusCode(201);
  }

  private Instant stored(String table, String column, UUID id) {
    try (var connection = dataSource.getConnection();
        var statement =
            connection.prepareStatement("SELECT " + column + " FROM " + table + " WHERE id = ?")) {
      statement.setObject(1, id);
      try (var rows = statement.executeQuery()) {
        assertTrue(rows.next());
        var time = rows.getTimestamp(1);
        return time == null ? null : time.toInstant();
      }
    } catch (SQLException e) {
      throw new IllegalStateException(e);
    }
  }

  private void set(String table, String column, UUID id, Instant at) {
    try (var connection = dataSource.getConnection();
        var statement =
            connection.prepareStatement(
                "UPDATE " + table + " SET " + column + " = ? WHERE id = ?")) {
      statement.setTimestamp(1, java.sql.Timestamp.from(at));
      statement.setObject(2, id);
      statement.executeUpdate();
    } catch (SQLException e) {
      throw new IllegalStateException(e);
    }
  }
}
