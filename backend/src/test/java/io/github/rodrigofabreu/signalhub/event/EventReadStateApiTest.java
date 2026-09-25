package io.github.rodrigofabreu.signalhub.event;

import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.github.rodrigofabreu.signalhub.TestProducers.asProducer;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.notNullValue;
import static org.hamcrest.Matchers.nullValue;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.github.rodrigofabreu.signalhub.TestClients;
import io.github.rodrigofabreu.signalhub.TestProducers;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import io.restassured.specification.RequestSpecification;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import java.util.function.Supplier;
import org.junit.jupiter.api.Test;

/**
 * Read state: marking events read and unread, in bulk, and the unread count, against real
 * PostgreSQL. Other test classes publish events into the same database, so assertions look at the
 * events each test publishes, and only the unread count test marks everything read first.
 */
@QuarkusTest
class EventReadStateApiTest {

  private static final String EVENTS = "/api/v1/events";
  private static final String UNREAD_COUNT = EVENTS + "/unread-count";
  private static final String MARK_READ = EVENTS + "/read";

  @Test
  void aNewEventIsUnread() {
    var event = publish(TestProducers.register("read-new"), "New");

    given().get(EVENTS + "/" + event).then().statusCode(200).body("readAt", nullValue());
  }

  @Test
  void marksAnEventReadForEveryClientAndKeepsTheFirstReadTime() {
    var producer = TestProducers.register("read-one");
    var event = publish(producer, "Read me");
    var phone = TestClients.register("read-phone");
    var tablet = TestClients.register("read-tablet");

    var readAt =
        asClient(phone.clientKey())
            .put(EVENTS + "/" + event + "/read")
            .then()
            .statusCode(200)
            .body("id", equalTo(event.toString()))
            .body("title", equalTo("Read me"))
            .body("readAt", notNullValue())
            .extract()
            .<String>path("readAt");

    // Another client sees it read, in the listing and by ID.
    asClient(tablet.clientKey())
        .queryParam("producerId", producer.id().toString())
        .get(EVENTS)
        .then()
        .statusCode(200)
        .body("items[0].readAt", equalTo(readAt));
    given().get(EVENTS + "/" + event).then().body("readAt", equalTo(readAt));

    // Marking it read again, from any client, changes nothing.
    asClient(tablet.clientKey())
        .put(EVENTS + "/" + event + "/read")
        .then()
        .statusCode(200)
        .body("readAt", equalTo(readAt));
    assertTrue(!Instant.parse(readAt).isAfter(Instant.now()));
  }

  @Test
  void marksAnEventUnreadAgain() {
    var event = publish(TestProducers.register("read-unread"), "Unread me");
    asAdmin().put(EVENTS + "/" + event + "/read").then().statusCode(200);

    asAdmin()
        .delete(EVENTS + "/" + event + "/read")
        .then()
        .statusCode(200)
        .body("id", equalTo(event.toString()))
        .body("readAt", nullValue());
    // Idempotent.
    asAdmin().delete(EVENTS + "/" + event + "/read").then().statusCode(200);
    given().get(EVENTS + "/" + event).then().body("readAt", nullValue());
  }

  @Test
  void marksEveryEventUpToOneReadAndLeavesNewerOnesUnread() {
    var producer = TestProducers.register("read-through");
    var oldest = publish(producer, "Oldest");
    var alreadyRead = publish(producer, "Already read");
    var through = publish(producer, "Through");
    var newer = publish(producer, "Newer");
    var readEarlier =
        asAdmin().put(EVENTS + "/" + alreadyRead + "/read").then().extract().<String>path("readAt");

    var marked =
        asAdmin()
            .contentType(ContentType.JSON)
            .body("{\"through\": \"" + through + "\"}")
            .post(MARK_READ)
            .then()
            .statusCode(200)
            .extract()
            .<Integer>path("marked");

    // Includes older unread events of other tests, but never the one already read.
    assertTrue(marked >= 2, "marked " + marked);
    var items =
        asAdmin()
            .queryParam("producerId", producer.id().toString())
            .get(EVENTS)
            .then()
            .statusCode(200)
            .extract()
            .jsonPath();
    assertEquals(
        List.of(newer.toString(), through.toString(), alreadyRead.toString(), oldest.toString()),
        items.getList("items.id"));
    assertEquals(null, items.getString("items[0].readAt"));
    assertNotNull(items.getString("items[1].readAt"));
    assertEquals(readEarlier, items.getString("items[2].readAt"));
    assertNotNull(items.getString("items[3].readAt"));

    // Nothing is left to mark up to that event.
    asAdmin()
        .contentType(ContentType.JSON)
        .body("{\"through\": \"" + through + "\"}")
        .post(MARK_READ)
        .then()
        .statusCode(200)
        .body("marked", equalTo(0));
  }

  @Test
  void countsUnreadEvents() {
    var producer = TestProducers.register("read-count");
    var first = publish(producer, "First");
    markReadThrough(first);
    assertEquals(0, unreadCount());

    var second = publish(producer, "Second");
    publish(producer, "Third");
    assertEquals(2, unreadCount());

    asAdmin().put(EVENTS + "/" + second + "/read").then().statusCode(200);
    assertEquals(1, unreadCount());
    asAdmin().delete(EVENTS + "/" + first + "/read").then().statusCode(200);
    assertEquals(2, unreadCount());

    var client = TestClients.register("read-count-client");
    asClient(client.clientKey())
        .get(UNREAD_COUNT)
        .then()
        .statusCode(200)
        .contentType(ContentType.JSON)
        .body("unread", equalTo(2));
  }

  @Test
  void unknownEventsAreNotFound() {
    var unknown = UUID.randomUUID();
    asAdmin()
        .put(EVENTS + "/" + unknown + "/read")
        .then()
        .statusCode(404)
        .body("title", equalTo("Event not found"));
    asAdmin().delete(EVENTS + "/" + unknown + "/read").then().statusCode(404);
    asAdmin()
        .contentType(ContentType.JSON)
        .body("{\"through\": \"" + unknown + "\"}")
        .post(MARK_READ)
        .then()
        .statusCode(404)
        .body("title", equalTo("Event not found"));
  }

  @Test
  void rejectsAnInvalidMarkReadBody() {
    asAdmin()
        .contentType(ContentType.JSON)
        .body("{}")
        .post(MARK_READ)
        .then()
        .statusCode(400)
        .body("violations.field", equalTo(List.of("through")));
    asAdmin()
        .contentType(ContentType.JSON)
        .body("{\"through\": \"not-a-uuid\"}")
        .post(MARK_READ)
        .then()
        .statusCode(400);
    asAdmin()
        .contentType(ContentType.JSON)
        .body("{\"through\": \"" + UUID.randomUUID() + "\", \"all\": true}")
        .post(MARK_READ)
        .then()
        .statusCode(400);
  }

  @Test
  void requiresAnOwnerCredential() {
    var producer = TestProducers.register("read-auth");
    var event = publish(producer, "Private");
    var markRead = "{\"through\": \"" + event + "\"}";
    List<Supplier<RequestSpecification>> strangers =
        List.of(
            () -> given(),
            () -> given().header("Authorization", "Bearer wrong"),
            // A producer key publishes; it does not manage the owner's inbox.
            () -> asProducer(producer.apiKey()));

    for (var stranger : strangers) {
      stranger
          .get()
          .put(EVENTS + "/" + event + "/read")
          .then()
          .statusCode(401)
          .header("WWW-Authenticate", containsString("Bearer"));
      stranger.get().delete(EVENTS + "/" + event + "/read").then().statusCode(401);
      stranger
          .get()
          .contentType(ContentType.JSON)
          .body(markRead)
          .post(MARK_READ)
          .then()
          .statusCode(401);
      stranger.get().get(UNREAD_COUNT).then().statusCode(401);
    }
    given().get(EVENTS + "/" + event).then().body("readAt", nullValue());
  }

  private static UUID publish(TestProducers.Registered producer, String title) {
    return UUID.fromString(
        asProducer(producer.apiKey())
            .contentType(ContentType.JSON)
            .body("{\"category\": \"INFO\", \"severity\": \"LOW\", \"title\": \"" + title + "\"}")
            .post(EVENTS)
            .then()
            .statusCode(201)
            .body("readAt", nullValue())
            .extract()
            .<String>path("id"));
  }

  private static void markReadThrough(UUID event) {
    asAdmin()
        .contentType(ContentType.JSON)
        .body("{\"through\": \"" + event + "\"}")
        .post(MARK_READ)
        .then()
        .statusCode(200);
  }

  private static int unreadCount() {
    return asAdmin().get(UNREAD_COUNT).then().statusCode(200).extract().path("unread");
  }
}
