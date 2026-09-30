package io.github.rodrigofabreu.signalhub.event;

import static io.github.rodrigofabreu.signalhub.TestClients.CLIENT;
import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.github.rodrigofabreu.signalhub.TestProducers.asProducer;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.containsInAnyOrder;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.nullValue;
import static org.junit.jupiter.api.Assertions.assertEquals;

import io.agroal.api.AgroalDataSource;
import io.github.rodrigofabreu.signalhub.TestClients;
import io.github.rodrigofabreu.signalhub.TestProducers;
import io.github.rodrigofabreu.signalhub.push.FakePushProvider;
import io.github.rodrigofabreu.signalhub.push.PushOutcome;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import io.restassured.path.json.JsonPath;
import jakarta.inject.Inject;
import java.sql.SQLException;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * The status summed up for the admin page's status panel, against real PostgreSQL and the fake push
 * provider: push configuration, the backlog as the database has it, the retries given up and the
 * retention setting, with the admin token only.
 */
@QuarkusTest
class StatusApiTest {

  private static final String STATUS = "/api/v1/admin/status";

  @Inject EventPushDispatcher dispatcher;
  @Inject FakePushProvider fake;
  @Inject AgroalDataSource dataSource;

  @BeforeEach
  void setUp() {
    // Events from other tests wait in the outbox too; send them before each test's own.
    dispatcher.dispatchPending();
    fake.answer((token, message) -> PushOutcome.delivered());
  }

  @Test
  void theStatusNeedsTheAdminToken() {
    given().get(STATUS).then().statusCode(401).body("status", equalTo(401));
    given()
        .header("Authorization", "Bearer wrong-admin-token-0123456789abcdef0123")
        .get(STATUS)
        .then()
        .statusCode(401);
    var client = TestClients.register("status-client-key");
    asClient(client.clientKey()).get(STATUS).then().statusCode(401);
  }

  @Test
  void theStatusSaysHowPushAndRetentionAreConfiguredAndNothingElse() {
    // Tests have only the fake provider, no push options for apps, and keep events forever.
    asAdmin()
        .get(STATUS)
        .then()
        .statusCode(200)
        .body(
            "keySet()",
            containsInAnyOrder(
                "pushProviders",
                "pushClientOptions",
                "pendingDispatches",
                "pendingRetries",
                "abandonedRetries",
                "eventRetentionSeconds"))
        .body("pushProviders", equalTo(List.of(FakePushProvider.NAME)))
        .body("pushClientOptions", nullValue())
        .body("eventRetentionSeconds", nullValue());
  }

  @Test
  void theBacklogIsReadFromTheDatabaseNow() throws SQLException {
    var producer = TestProducers.register("status-backlog");
    var eventId = publish(producer.apiKey());
    // Not dispatched yet: the dispatcher has not run since.
    var status = status();
    assertEquals(count("push_dispatches"), status.getLong("pendingDispatches"));
    assertEquals(1, count("push_dispatches WHERE event_id = '" + eventId + "'"));

    dispatcher.dispatchPending();
    assertEquals(0, status().getLong("pendingDispatches"));
  }

  @Test
  void retriesWaitingAndGivenUpAreCounted() throws SQLException {
    clientWithTarget();
    fake.answer((to, message) -> new PushOutcome(PushOutcome.Status.TRANSIENT_FAILURE, "down"));
    var abandoned = status().getLong("abandonedRetries");
    var eventId = publish(TestProducers.register("status-retries").apiKey());
    dispatcher.dispatchPending();
    var retrying = count("push_retries WHERE event_id = '" + eventId + "'");
    var status = status();
    assertEquals(count("push_retries"), status.getLong("pendingRetries"));
    assertEquals(abandoned, status.getLong("abandonedRetries"));

    for (var attempt = 2; attempt <= EventPushDispatcher.MAX_ATTEMPTS; attempt++) {
      execute(
          "UPDATE push_retries SET next_attempt_at = now() - interval '1 second'"
              + " WHERE event_id = '"
              + eventId
              + "'");
      dispatcher.dispatchPending();
    }

    status = status();
    assertEquals(abandoned + retrying, status.getLong("abandonedRetries"));
    assertEquals(count("push_retries"), status.getLong("pendingRetries"));
  }

  private static JsonPath status() {
    return asAdmin().get(STATUS).then().statusCode(200).extract().jsonPath();
  }

  private static UUID publish(String apiKey) {
    return UUID.fromString(
        asProducer(apiKey)
            .contentType(ContentType.JSON)
            .body(Map.of("category", "ACTION_REQUIRED", "severity", "HIGH", "title", "Status"))
            .post("/api/v1/events")
            .then()
            .statusCode(201)
            .extract()
            .path("id"));
  }

  private static void clientWithTarget() {
    var client = TestClients.register("status-push");
    asClient(client.clientKey())
        .contentType(ContentType.JSON)
        .body(Map.of("provider", FakePushProvider.NAME, "token", "status-" + UUID.randomUUID()))
        .put(CLIENT + "/push-target")
        .then()
        .statusCode(200);
  }

  private long count(String fromWhere) throws SQLException {
    try (var connection = dataSource.getConnection();
        var statement = connection.createStatement();
        var rows = statement.executeQuery("SELECT count(*) FROM " + fromWhere)) {
      rows.next();
      return rows.getLong(1);
    }
  }

  private void execute(String sql) throws SQLException {
    try (var connection = dataSource.getConnection();
        var statement = connection.createStatement()) {
      statement.executeUpdate(sql);
    }
  }
}
