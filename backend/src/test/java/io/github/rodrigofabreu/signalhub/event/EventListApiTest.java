package io.github.rodrigofabreu.signalhub.event;

import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.github.rodrigofabreu.signalhub.TestProducers.asProducer;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.nullValue;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.agroal.api.AgroalDataSource;
import io.github.rodrigofabreu.signalhub.TestProducers;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import io.restassured.path.json.JsonPath;
import io.restassured.specification.RequestSpecification;
import jakarta.inject.Inject;
import java.nio.charset.StandardCharsets;
import java.sql.SQLException;
import java.sql.Statement;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.function.UnaryOperator;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

/**
 * {@code GET /api/v1/events}, the event inbox, against real PostgreSQL. Other test classes publish
 * events into the same database, so each test registers its own producers and filters by them
 * unless it is about the unfiltered listing.
 */
@QuarkusTest
class EventListApiTest {

  private static final String EVENTS = "/api/v1/events";

  @Inject AgroalDataSource dataSource;

  @Test
  void requiresAnOwnerCredential() {
    var producer = TestProducers.register("list-auth");
    given().get(EVENTS).then().statusCode(401).header("WWW-Authenticate", containsString("Bearer"));
    given().header("Authorization", "Bearer wrong").get(EVENTS).then().statusCode(401);
    // A producer key publishes; it does not read the inbox.
    asProducer(producer.apiKey()).get(EVENTS).then().statusCode(401);
  }

  @Test
  void returnsTheNewestEventFirstInItsCanonicalForm() {
    var producer = TestProducers.register("list-newest");
    publish(producer, "INFO", "LOW", "Older");
    var newest =
        publish(
            producer,
            """
            {"context": "signalhub", "category": "BLOCKED", "severity": "HIGH",
             "title": "Newest", "message": "Details", "metadata": {"run": 7},
             "occurredAt": "2026-09-25T14:03:00+02:00"}
            """);

    var page =
        asAdmin()
            .queryParam("limit", 1)
            .get(EVENTS)
            .then()
            .statusCode(200)
            .contentType(ContentType.JSON)
            .extract()
            .jsonPath();

    assertEquals(1, page.getList("items").size());
    assertEquals(newest.getMap("$"), page.getMap("items[0]"));
    assertEquals(producer.name(), page.getString("items[0].producer.name"));
    assertEquals(7, page.getInt("items[0].metadata.run"));
    assertNotNull(page.getString("nextCursor"));
  }

  @Test
  void pagesThroughEveryEventExactlyOnceNewestFirst() {
    var producer = TestProducers.register("list-pages");
    var published = new ArrayList<String>();
    for (int i = 0; i < 5; i++) {
      published.add(publish(producer, "INFO", "LOW", "Event " + i).getString("id"));
    }

    var pages = pages(spec -> spec.queryParam("producerId", producer.id()), 2);

    assertEquals(List.of(2, 2, 1), pages.stream().map(p -> p.getList("items").size()).toList());
    assertEquals(published.reversed(), ids(pages));
  }

  @Test
  void aFullLastPageHasNoNextCursor() {
    var producer = TestProducers.register("list-full-page");
    for (int i = 0; i < 4; i++) {
      publish(producer, "INFO", "LOW", "Event " + i);
    }

    var pages = pages(spec -> spec.queryParam("producerId", producer.id()), 2);

    assertEquals(2, pages.size());
    assertNull(pages.get(1).getString("nextCursor"));
  }

  @Test
  void anEmptyResultIsAnEmptyPage() {
    asAdmin()
        .queryParam("producerId", UUID.randomUUID())
        .get(EVENTS)
        .then()
        .statusCode(200)
        .body("items.size()", equalTo(0))
        .body("nextCursor", nullValue());
  }

  @Test
  void eventsPublishedMeanwhileDoNotShiftLaterPages() {
    var producer = TestProducers.register("list-stable");
    var oldest = publish(producer, "INFO", "LOW", "Oldest").getString("id");
    publish(producer, "INFO", "LOW", "Middle");
    publish(producer, "INFO", "LOW", "Newest");
    var first = page(spec -> spec.queryParam("producerId", producer.id()).queryParam("limit", 2));

    publish(producer, "INFO", "LOW", "Published after the first page");
    var second =
        page(
            spec ->
                spec.queryParam("producerId", producer.id())
                    .queryParam("limit", 2)
                    .queryParam("cursor", first.getString("nextCursor")));

    assertEquals(List.of(oldest), second.getList("items.id"));
    assertNull(second.getString("nextCursor"));
  }

  @Test
  void eventsCreatedAtTheSameInstantAreOrderedById() throws SQLException {
    var producer = TestProducers.register("list-ties");
    List<String> expected;
    try (var connection = dataSource.getConnection();
        var statement = connection.createStatement()) {
      for (int i = 0; i < 3; i++) {
        statement.executeUpdate(
            "INSERT INTO events (id, producer_id, category, severity, title, metadata, created_at)"
                + " VALUES (gen_random_uuid(), '"
                + producer.id()
                + "', 'INFO', 'LOW', 'Tie', '{}', '2026-01-01T00:00:00Z')");
      }
      expected = new ArrayList<>();
      try (var rows =
          statement.executeQuery(
              "SELECT id FROM events WHERE producer_id = '"
                  + producer.id()
                  + "' ORDER BY id DESC")) {
        while (rows.next()) {
          expected.add(rows.getString(1));
        }
      }
    }

    var pages = pages(spec -> spec.queryParam("producerId", producer.id()), 1);

    assertEquals(expected, ids(pages));
  }

  @Test
  void filtersByProducer() {
    var first = TestProducers.register("list-producer-a");
    var second = TestProducers.register("list-producer-b");
    var a = publish(first, "INFO", "LOW", "A").getString("id");
    var b = publish(second, "INFO", "LOW", "B").getString("id");

    assertEquals(List.of(a), ids(spec -> spec.queryParam("producerId", first.id())));
    assertEquals(
        List.of(b, a),
        ids(
            spec ->
                spec.queryParam("producerId", first.id()).queryParam("producerId", second.id())));
  }

  @Test
  void filtersByCategoryAndSeverity() {
    var producer = TestProducers.register("list-enums");
    var blockedHigh = publish(producer, "BLOCKED", "HIGH", "Blocked, high").getString("id");
    var infoCritical = publish(producer, "INFO", "CRITICAL", "Info, critical").getString("id");
    var infoLow = publish(producer, "INFO", "LOW", "Info, low").getString("id");
    publish(producer, "COMPLETED", "HIGH", "Completed, high");

    UnaryOperator<RequestSpecification> ofProducer =
        spec -> spec.queryParam("producerId", producer.id());
    assertEquals(
        List.of(infoLow, infoCritical, blockedHigh),
        ids(
            spec ->
                ofProducer
                    .apply(spec)
                    .queryParam("category", "INFO")
                    .queryParam("category", "BLOCKED")));
    assertEquals(
        List.of(infoCritical, blockedHigh),
        ids(
            spec ->
                ofProducer
                    .apply(spec)
                    .queryParam("category", "INFO", "BLOCKED")
                    .queryParam("severity", "HIGH", "CRITICAL")));
    assertEquals(
        List.of(infoLow),
        ids(
            spec ->
                ofProducer
                    .apply(spec)
                    .queryParam("category", "INFO")
                    .queryParam("severity", "LOW")));
  }

  @Test
  void filtersByReadState() {
    var producer = TestProducers.register("list-read");
    var readInfo = publish(producer, "INFO", "LOW", "Read info").getString("id");
    var unreadInfo = publish(producer, "INFO", "LOW", "Unread info").getString("id");
    var unreadBlocked = publish(producer, "BLOCKED", "HIGH", "Unread blocked").getString("id");
    markRead(readInfo);

    UnaryOperator<RequestSpecification> ofProducer =
        spec -> spec.queryParam("producerId", producer.id());
    assertEquals(
        List.of(unreadBlocked, unreadInfo),
        ids(spec -> ofProducer.apply(spec).queryParam("read", false)));
    assertEquals(List.of(readInfo), ids(spec -> ofProducer.apply(spec).queryParam("read", true)));
    assertEquals(
        List.of(unreadInfo),
        ids(
            spec ->
                ofProducer.apply(spec).queryParam("read", false).queryParam("category", "INFO")));
    assertEquals(List.of(unreadBlocked, unreadInfo, readInfo), ids(spec -> ofProducer.apply(spec)));
  }

  @Test
  void pagesThroughUnreadEventsWhileEventsAreMarkedReadOrUnread() {
    var producer = TestProducers.register("list-unread-pages");
    var published = new ArrayList<String>();
    for (int i = 0; i < 5; i++) {
      published.add(publish(producer, "INFO", "LOW", "Event " + i).getString("id"));
    }
    markRead(published.get(0));
    UnaryOperator<RequestSpecification> unreadOfProducer =
        spec ->
            spec.queryParam("producerId", producer.id())
                .queryParam("read", false)
                .queryParam("limit", 2);
    var first = page(unreadOfProducer);
    assertEquals(List.of(published.get(4), published.get(3)), first.getList("items.id"));

    // Between pages: one event of the first page and one not listed yet are read, and one read
    // before is unread again.
    markRead(published.get(3));
    markRead(published.get(1));
    markUnread(published.get(0));
    var second =
        page(
            spec ->
                unreadOfProducer.apply(spec).queryParam("cursor", first.getString("nextCursor")));

    // The cursor is a position: the next page starts after it whatever changed, never repeats the
    // first page, and lists the events that are unread now.
    assertEquals(List.of(published.get(2), published.get(0)), second.getList("items.id"));
    assertNull(second.getString("nextCursor"));
  }

  @Test
  void theUnreadListingIsServedByThePartialUnreadIndex() throws SQLException {
    // The predicates the listing sends for read=false, first page and later pages. Sequential
    // scans are disabled because the test database is small enough to prefer them.
    var firstPage =
        "SELECT id FROM events WHERE read_at IS NULL ORDER BY created_at DESC, id DESC LIMIT 51";
    var laterPage =
        "SELECT id FROM events WHERE read_at IS NULL AND (created_at, id) < (now(), gen_random_uuid())"
            + " ORDER BY created_at DESC, id DESC LIMIT 51";
    try (var connection = dataSource.getConnection();
        var statement = connection.createStatement()) {
      connection.setAutoCommit(false);
      try {
        statement.execute("SET LOCAL enable_seqscan = off");
        for (var query : List.of(firstPage, laterPage)) {
          assertTrue(
              plan(statement, query).contains("events_unread_created_at_id_idx"),
              () -> "not served by the unread index: " + query);
        }
      } finally {
        connection.rollback();
      }
    }
  }

  @Test
  void filtersByCreationTime() {
    var producer = TestProducers.register("list-time");
    var oldest = publish(producer, "INFO", "LOW", "Oldest").getString("id");
    var middle = publish(producer, "INFO", "LOW", "Middle");
    var newest = publish(producer, "INFO", "LOW", "Newest").getString("id");
    var middleCreatedAt = middle.getString("createdAt");

    UnaryOperator<RequestSpecification> ofProducer =
        spec -> spec.queryParam("producerId", producer.id());
    assertEquals(
        List.of(newest, middle.getString("id")),
        ids(spec -> ofProducer.apply(spec).queryParam("createdFrom", middleCreatedAt)));
    assertEquals(
        List.of(oldest),
        ids(spec -> ofProducer.apply(spec).queryParam("createdBefore", middleCreatedAt)));
    assertEquals(
        List.of(middle.getString("id")),
        ids(
            spec ->
                ofProducer
                    .apply(spec)
                    .queryParam("createdFrom", middleCreatedAt)
                    .queryParam("createdBefore", newestCreatedAtOf(producer))));
  }

  @Test
  void acceptsTimestampsWithAnyOffset() {
    var producer = TestProducers.register("list-offset");
    var event = publish(producer, "INFO", "LOW", "Offset");
    var createdAt = Instant.parse(event.getString("createdAt"));
    var sameInstantInCet = createdAt.atOffset(ZoneOffset.ofHours(2)).toString();

    assertEquals(
        List.of(event.getString("id")),
        ids(
            spec ->
                spec.queryParam("producerId", producer.id())
                    .queryParam("createdFrom", sameInstantInCet)));
  }

  @ParameterizedTest
  @CsvSource({
    "limit, 0",
    "limit, 101",
    "limit, ten",
    "category, NOPE",
    "category, info",
    "severity, URGENT",
    "producerId, not-a-uuid",
    "producerId, 1-1-1-1-1",
    "createdFrom, 2026-09-25T14:03:00",
    "createdFrom, 1758800000",
    "createdBefore, +10000-01-01T00:00:00Z",
    "cursor, not-a-cursor",
    "read, yes",
    "read, FALSE",
    "read, 0",
  })
  void rejectsAnInvalidParameterNamingIt(String parameter, String value) {
    asAdmin()
        .queryParam(parameter, value)
        .get(EVENTS)
        .then()
        .statusCode(400)
        .contentType(ContentType.JSON)
        .body("title", equalTo("Invalid request"))
        .body("violations.size()", equalTo(1))
        .body("violations[0].field", equalTo(parameter));
  }

  @Test
  void rejectsACursorOfAnotherVersion() {
    var foreign =
        Base64.getUrlEncoder()
            .withoutPadding()
            .encodeToString(("2:0:" + UUID.randomUUID()).getBytes(StandardCharsets.UTF_8));
    asAdmin()
        .queryParam("cursor", foreign)
        .get(EVENTS)
        .then()
        .statusCode(400)
        .body("violations[0].field", equalTo("cursor"));
  }

  @Test
  void reportsEveryInvalidParameterAtOnce() {
    asAdmin()
        .queryParam("limit", 0)
        .queryParam("severity", "URGENT")
        .get(EVENTS)
        .then()
        .statusCode(400)
        .body("violations.field", equalTo(List.of("limit", "severity")));
  }

  private static JsonPath publish(TestProducers.Registered producer, String body) {
    return asProducer(producer.apiKey())
        .contentType(ContentType.JSON)
        .body(body)
        .post(EVENTS)
        .then()
        .statusCode(201)
        .extract()
        .jsonPath();
  }

  private static JsonPath publish(
      TestProducers.Registered producer, String category, String severity, String title) {
    return publish(
        producer,
        "{\"category\": \""
            + category
            + "\", \"severity\": \""
            + severity
            + "\", \"title\": \""
            + title
            + "\"}");
  }

  private static void markRead(String event) {
    asAdmin().put(EVENTS + "/" + event + "/read").then().statusCode(200);
  }

  private static void markUnread(String event) {
    asAdmin().delete(EVENTS + "/" + event + "/read").then().statusCode(200);
  }

  private static String plan(Statement statement, String query) throws SQLException {
    var plan = new StringBuilder();
    try (var rows = statement.executeQuery("EXPLAIN " + query)) {
      while (rows.next()) {
        plan.append(rows.getString(1)).append('\n');
      }
    }
    return plan.toString();
  }

  private static JsonPath page(UnaryOperator<RequestSpecification> query) {
    return query.apply(asAdmin()).get(EVENTS).then().statusCode(200).extract().jsonPath();
  }

  /** Follows nextCursor from the first page to the last, with the same filters on every request. */
  private static List<JsonPath> pages(UnaryOperator<RequestSpecification> filters, int limit) {
    var pages = new ArrayList<JsonPath>();
    String cursor = null;
    do {
      var after = cursor;
      var page =
          page(
              spec -> {
                var request = filters.apply(spec).queryParam("limit", limit);
                return after == null ? request : request.queryParam("cursor", after);
              });
      pages.add(page);
      cursor = page.getString("nextCursor");
    } while (cursor != null && pages.size() < 100);
    return pages;
  }

  private static List<String> ids(List<JsonPath> pages) {
    return pages.stream().flatMap(p -> p.<String>getList("items.id").stream()).toList();
  }

  private static List<String> ids(UnaryOperator<RequestSpecification> filters) {
    return ids(pages(filters, 100));
  }

  private static String newestCreatedAtOf(TestProducers.Registered producer) {
    var newest = page(spec -> spec.queryParam("producerId", producer.id()).queryParam("limit", 1));
    Map<String, Object> event = newest.getMap("items[0]");
    return (String) event.get("createdAt");
  }
}
