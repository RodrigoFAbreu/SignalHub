package io.github.rodrigofabreu.signalhub.event;

import static io.github.rodrigofabreu.signalhub.TestClients.CLIENT;
import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.github.rodrigofabreu.signalhub.TestProducers.asProducer;
import static org.hamcrest.Matchers.containsInAnyOrder;
import static org.hamcrest.Matchers.empty;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.hasKey;
import static org.hamcrest.Matchers.not;
import static org.junit.jupiter.api.Assertions.assertEquals;

import io.agroal.api.AgroalDataSource;
import io.github.rodrigofabreu.signalhub.TestClients;
import io.github.rodrigofabreu.signalhub.TestProducers;
import io.github.rodrigofabreu.signalhub.TestUsers;
import io.github.rodrigofabreu.signalhub.push.FakePushProvider;
import io.github.rodrigofabreu.signalhub.push.PushOutcome;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import io.restassured.response.ValidatableResponse;
import jakarta.inject.Inject;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * The operator's event listing: the total count of the events matching its filters, and a summary
 * of how each event's pushes went, with a filter by it. On real PostgreSQL. Delivery records are
 * written directly, to set up every combination; one test goes through the dispatcher instead.
 */
@QuarkusTest
class EventListPushApiTest {

  private static final String EVENTS = "/api/v1/events";
  private static final int MAX = EventPushDispatcher.MAX_ATTEMPTS;

  @Inject AgroalDataSource dataSource;
  @Inject EventPushDispatcher dispatcher;
  @Inject FakePushProvider fake;

  private TestProducers.Registered producer;
  private TestClients.Registered first;
  private TestClients.Registered second;

  @BeforeEach
  void setUp() {
    dispatcher.dispatchPending();
    fake.answer((token, message) -> PushOutcome.delivered());
    producer = TestProducers.register("list-push");
    first = TestClients.register("list-push-first");
    second = TestClients.register("list-push-second");
  }

  @Test
  void thePageCountsEveryMatchingEventWhenAskedWhateverThePageHolds() {
    var severities = List.of("NORMAL", "NORMAL", "NORMAL", "CRITICAL");
    severities.forEach(severity -> publish(severity, "a title"));

    var firstPage = list("producerId", producer.id(), "total", true, "limit", 2);
    firstPage.body("items.size()", equalTo(2)).body("total", equalTo(4));
    // The cursor does not shrink the total: it counts the matches, not what is left.
    list(
            "producerId",
            producer.id(),
            "total",
            true,
            "limit",
            2,
            "cursor",
            firstPage.extract().path("nextCursor"))
        .body("items.size()", equalTo(2))
        .body("total", equalTo(4));
    list("producerId", producer.id(), "severity", "CRITICAL", "total", true)
        .body("total", equalTo(1));
    list("producerId", producer.id(), "severity", "LOW", "total", true)
        .body("items", empty())
        .body("total", equalTo(0));
    list("producerId", producer.id(), "read", true, "total", true).body("total", equalTo(0));
    list("producerId", producer.id(), "total", false).body("$", not(hasKey("total")));
    list("producerId", producer.id()).body("$", not(hasKey("total")));
  }

  @Test
  void theTotalOfAUsersViewFollowsTheUserFilter() {
    publish("NORMAL", "mine");
    var other = TestUsers.create("list-push-nobody", "BASIC");

    list("userId", first.userId(), "producerId", producer.id(), "total", true)
        .body("total", equalTo(1));
    list("userId", other.id(), "producerId", producer.id(), "total", true)
        .body("items", empty())
        .body("total", equalTo(0));
  }

  @Test
  void eachEventSaysHowItsPushesWentAndTheListingFiltersByIt() throws SQLException {
    var expected = new LinkedHashMap<String, String>();
    expected.put(
        eventWith(rec(first, MAX, "TRANSIENT_FAILURE"), rec(second, 1, "DELIVERED")), "GAVE_UP");
    expected.put(
        eventWith(rec(first, 1, "PERMANENT_FAILURE"), rec(second, 1, "DELIVERED")), "FAILED");
    expected.put(eventWith(rec(first, 1, "INVALID_TARGET"), rec(second, 1, "FILTERED")), "FAILED");
    expected.put(eventWith(rec(first, 1, "UNSUPPORTED_PROVIDER")), "FAILED");
    expected.put(
        eventWith(rec(first, 1, "TRANSIENT_FAILURE"), rec(second, 1, "DELIVERED")),
        "WAITING_FOR_RETRY");
    // A retry that went through, or that found the device paused, is the device's last word.
    expected.put(eventWith(rec(first, 1, "TRANSIENT_FAILURE"), rec(first, 2, "DELIVERED")), "SENT");
    expected.put(
        eventWith(rec(first, 1, "TRANSIENT_FAILURE"), rec(first, 2, "FILTERED")), "NOT_SENT");
    expected.put(eventWith(rec(first, 1, "DELIVERED"), rec(second, 1, "FILTERED")), "SENT");
    expected.put(eventWith(rec(first, 1, "FILTERED"), rec(second, 1, "NO_TARGET")), "NOT_SENT");
    expected.put(pendingEvent(), "PENDING");
    expected.put(eventWith(), "NOBODY_TO_REACH");

    var items = list("producerId", producer.id(), "limit", 100).extract().jsonPath();
    for (var entry : expected.entrySet()) {
      assertEquals(
          entry.getValue(),
          items.getString("items.find { it.id == '" + entry.getKey() + "' }.push"),
          entry.getKey());
    }
    for (var summary : PushSummary.values()) {
      var ids = idsWith(expected, summary.name());
      var filtered = list("producerId", producer.id(), "push", summary, "total", true);
      filtered.body("items.id", containsInAnyOrder(ids.toArray()));
      filtered.body("total", equalTo(ids.size()));
    }
    var problems = new ArrayList<>(idsWith(expected, "FAILED"));
    problems.addAll(idsWith(expected, "GAVE_UP"));
    list("producerId", producer.id(), "push", "FAILED", "push", "GAVE_UP")
        .body("items.id", containsInAnyOrder(problems.toArray()));
  }

  @Test
  void theFilterCombinesWithTheOtherFiltersAndPaging() throws SQLException {
    var failedCritical = eventWith("CRITICAL", rec(first, 1, "PERMANENT_FAILURE"));
    var failedInfo = eventWith("NORMAL", rec(first, 1, "PERMANENT_FAILURE"));
    var failedRead = eventWith("NORMAL", rec(first, 1, "PERMANENT_FAILURE"));
    var gaveUp = eventWith("NORMAL", rec(first, MAX, "TRANSIENT_FAILURE"));
    eventWith("NORMAL", rec(first, 1, "DELIVERED"));
    asAdmin().put(EVENTS + "/" + failedRead + "/read").then().statusCode(200);

    var problem = new Object[] {"producerId", producer.id(), "push", "FAILED", "push", "GAVE_UP"};
    list(with(problem, "severity", "CRITICAL", "total", true))
        .body("items.id", containsInAnyOrder(failedCritical))
        .body("total", equalTo(1));
    list(with(problem, "read", false, "total", true))
        .body("items.id", containsInAnyOrder(failedCritical, failedInfo, gaveUp))
        .body("total", equalTo(3));
    // Paging through the filtered list one at a time, newest first, shows each exactly once.
    var seen = new ArrayList<String>();
    String cursor = null;
    do {
      var page =
          cursor == null
              ? list(with(problem, "limit", 1, "total", true))
              : list(with(problem, "limit", 1, "total", true, "cursor", cursor));
      page.body("total", equalTo(4));
      seen.addAll(page.extract().<List<String>>path("items.id"));
      cursor = page.extract().path("nextCursor");
    } while (cursor != null);
    assertEquals(List.of(gaveUp, failedRead, failedInfo, failedCritical), seen);
  }

  @Test
  void aPushThroughTheDispatcherIsSummarisedAsItGoes() throws SQLException {
    // Alone with its own user, so no device of other tests is among those pushed to.
    var user = TestUsers.create("list-push-owner", "MOD");
    producer = TestProducers.register("list-push-own", user.id(), "PRIVATE");
    var client = TestClients.registerFor(user.id(), "list-push-dispatched");
    asClient(client.clientKey())
        .contentType(ContentType.JSON)
        .body(Map.of("provider", FakePushProvider.NAME, "token", "list-push-" + UUID.randomUUID()))
        .put(CLIENT + "/push-target")
        .then()
        .statusCode(200);
    var delivered = publish("NORMAL", "delivered");
    dispatcher.dispatchPending();
    assertEquals("SENT", pushOf(delivered));

    fake.answer((to, message) -> new PushOutcome(PushOutcome.Status.TRANSIENT_FAILURE, "HTTP 503"));
    var retried = publish("NORMAL", "retried");
    dispatcher.dispatchPending();
    assertEquals("WAITING_FOR_RETRY", pushOf(retried));
    for (var attempt = 2; attempt <= MAX; attempt++) {
      execute(
          "UPDATE push_retries SET next_attempt_at = now() - interval '1 second'"
              + " WHERE event_id = '"
              + retried
              + "'");
      dispatcher.dispatchPending();
    }
    assertEquals("GAVE_UP", pushOf(retried));
    list("producerId", producer.id(), "push", "GAVE_UP")
        .body("items.id", containsInAnyOrder(retried.toString()));

    fake.answer((to, message) -> new PushOutcome(PushOutcome.Status.PERMANENT_FAILURE, "HTTP 400"));
    var refused = publish("NORMAL", "refused");
    dispatcher.dispatchPending();
    assertEquals("FAILED", pushOf(refused));
  }

  @Test
  void aClientKeyListsAsBeforeAndCannotAskForTheseAdditions() {
    publish("NORMAL", "for a client");

    asClient(first.clientKey())
        .queryParam("producerId", producer.id())
        .get(EVENTS)
        .then()
        .statusCode(200)
        .body("$", not(hasKey("total")))
        .body("items[0]", not(hasKey("push")));
    asClient(first.clientKey())
        .queryParam("total", true)
        .queryParam("push", "FAILED")
        .get(EVENTS)
        .then()
        .statusCode(400)
        .body("violations.field", containsInAnyOrder("push", "total"));
    asClient(first.clientKey()).queryParam("total", false).get(EVENTS).then().statusCode(200);
  }

  @Test
  void theNewParametersAreValidated() {
    asAdmin()
        .queryParam("total", "maybe")
        .queryParam("push", "BROKEN")
        .get(EVENTS)
        .then()
        .statusCode(400)
        .body("violations.field", hasItem("total"))
        .body("violations.field", hasItem("push"));
  }

  @Test
  void otherResponsesCarryNeitherAPushSummaryNorATotal() {
    var id = publish("NORMAL", "single");

    asAdmin().get(EVENTS + "/" + id).then().statusCode(200).body("$", not(hasKey("push")));
    asProducer(producer.apiKey())
        .contentType(ContentType.JSON)
        .body(Map.of("category", "INFO", "severity", "NORMAL", "title", "created"))
        .post(EVENTS)
        .then()
        .statusCode(201)
        .body("$", not(hasKey("push")));
  }

  private String pushOf(UUID eventId) {
    return list("producerId", producer.id(), "limit", 100)
        .extract()
        .jsonPath()
        .getString("items.find { it.id == '" + eventId + "' }.push");
  }

  private static List<String> idsWith(Map<String, String> expected, String summary) {
    return expected.entrySet().stream()
        .filter(entry -> entry.getValue().equals(summary))
        .map(Map.Entry::getKey)
        .toList();
  }

  private static Object[] with(Object[] base, Object... more) {
    var all = new ArrayList<>(List.of(base));
    all.addAll(List.of(more));
    return all.toArray();
  }

  private static ValidatableResponse list(Object... queryParams) {
    var request = asAdmin();
    for (var i = 0; i < queryParams.length; i += 2) {
      request = request.queryParam((String) queryParams[i], queryParams[i + 1]);
    }
    return request.get(EVENTS).then().statusCode(200);
  }

  private record Rec(TestClients.Registered client, int attempt, String outcome) {}

  private static Rec rec(TestClients.Registered client, int attempt, String outcome) {
    return new Rec(client, attempt, outcome);
  }

  private String eventWith(Rec... records) throws SQLException {
    return eventWith("NORMAL", records);
  }

  /** An event already dispatched (out of the outbox) with these delivery records. */
  private String eventWith(String severity, Rec... records) throws SQLException {
    var id = publish(severity, "with records");
    execute("DELETE FROM push_dispatches WHERE event_id = '" + id + "'");
    for (var record : records) {
      execute(
          "INSERT INTO event_deliveries (event_id, client_id, attempt, outcome, at) VALUES ('"
              + id
              + "', '"
              + record.client().id()
              + "', "
              + record.attempt()
              + ", '"
              + record.outcome()
              + "', clock_timestamp())");
    }
    return id.toString();
  }

  /** An event whose push still waits in the outbox. */
  private String pendingEvent() {
    return publish("NORMAL", "pending").toString();
  }

  private UUID publish(String severity, String title) {
    return UUID.fromString(
        asProducer(producer.apiKey())
            .contentType(ContentType.JSON)
            .body(Map.of("category", "INFO", "severity", severity, "title", title))
            .post(EVENTS)
            .then()
            .statusCode(201)
            .extract()
            .path("id"));
  }

  private void execute(String sql) throws SQLException {
    try (var connection = dataSource.getConnection();
        var statement = connection.createStatement()) {
      statement.execute(sql);
    }
  }
}
