package io.github.rodrigofabreu.signalhub.event;

import static io.github.rodrigofabreu.signalhub.TestClients.CLIENT;
import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.github.rodrigofabreu.signalhub.TestProducers.asProducer;
import static org.hamcrest.Matchers.contains;
import static org.hamcrest.Matchers.containsInAnyOrder;
import static org.hamcrest.Matchers.empty;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.everyItem;
import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.not;
import static org.junit.jupiter.api.Assertions.assertEquals;

import io.github.rodrigofabreu.signalhub.TestClients;
import io.github.rodrigofabreu.signalhub.TestProducers;
import io.github.rodrigofabreu.signalhub.TestUsers;
import io.github.rodrigofabreu.signalhub.push.FakePushProvider;
import io.github.rodrigofabreu.signalhub.push.PushOutcome;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import jakarta.inject.Inject;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * The operator's view of traffic per user: the events listing filtered by user, an event's
 * recipients and the user of each delivery, and a user's recent events and deliveries. Two users,
 * each with a device, a private producer of their own and a subscription to the other's public one.
 * Against real PostgreSQL with the fake push provider.
 */
@QuarkusTest
class UserTrafficApiTest {

  private static final String EVENTS = "/api/v1/events";

  @Inject EventPushDispatcher dispatcher;
  @Inject FakePushProvider fake;

  @BeforeEach
  void setUp() {
    // Events from other tests wait in the outbox too; send them before each test's own.
    dispatcher.dispatchPending();
    fake.answer((token, message) -> PushOutcome.delivered());
  }

  private record Person(
      TestUsers.Created user, TestClients.Registered device, TestProducers.Registered producer) {}

  private static Person person(String role, String visibility) {
    var user = TestUsers.create("traffic-" + role, role);
    var device = TestClients.registerFor(user.id(), "traffic-phone-" + role);
    asClient(device.clientKey())
        .contentType(ContentType.JSON)
        .body(Map.of("provider", FakePushProvider.NAME, "token", "traffic-" + UUID.randomUUID()))
        .put(CLIENT + "/push-target")
        .then()
        .statusCode(200);
    return new Person(user, device, TestProducers.register("traffic", user.id(), visibility));
  }

  @Test
  void theListingFiltersByTheProducersAUserOwnsOrIsSubscribedTo() {
    var anna = person("BASIC", "PUBLIC");
    var ben = person("MOD", "PRIVATE");
    TestUsers.subscribe(ben.user().id(), anna.producer().id());
    var annas = publish(anna.producer(), "Anna's");
    var bens = publish(ben.producer(), "Ben's");

    // Anna owns and receives her producer's; Ben owns his, and is subscribed to Anna's (an
    // owner is subscribed to their own producer from its creation).
    assertEquals(List.of(annas), listed(anna.user().id(), null));
    assertEquals(List.of(bens, annas), listed(ben.user().id(), null));
    assertEquals(List.of(bens), listed(ben.user().id(), "OWNED"));
    assertEquals(List.of(bens, annas), listed(ben.user().id(), "SUBSCRIBED"));
    assertEquals(List.of(annas), listed(anna.user().id(), "OWNED"));
    // It combines with the other filters.
    asAdmin()
        .queryParam("userId", ben.user().id().toString())
        .queryParam("producerId", anna.producer().id().toString())
        .get(EVENTS)
        .then()
        .statusCode(200)
        .body("items.id", contains(annas.toString()));
  }

  @Test
  void aUserWithNoProducersOrSubscriptionsHasNoEvents() {
    var anna = person("BASIC", "PRIVATE");
    publish(anna.producer(), "Anna's");
    var nobody = TestUsers.create("traffic-nobody", "BASIC");
    assertEquals(List.of(), listed(nobody.id(), null));
  }

  @Test
  void theUserFilterIsTheOperatorsAndNeedsAnExistingUser() {
    var anna = person("BASIC", "PRIVATE");
    publish(anna.producer(), "Anna's");

    asClient(anna.device().clientKey())
        .queryParam("userId", anna.user().id().toString())
        .get(EVENTS)
        .then()
        .statusCode(400)
        .body("violations.field", contains("userId"));
    asAdmin().queryParam("relation", "OWNED").get(EVENTS).then().statusCode(400);
    asAdmin()
        .queryParam("userId", anna.user().id().toString())
        .queryParam("relation", "SOMETIMES")
        .get(EVENTS)
        .then()
        .statusCode(400)
        .body("violations.field", contains("relation"));
    asAdmin().queryParam("userId", "nope").get(EVENTS).then().statusCode(400);
    asAdmin().queryParam("userId", UUID.randomUUID().toString()).get(EVENTS).then().statusCode(404);
    asProducer(anna.producer().apiKey()).get(EVENTS).then().statusCode(401);
  }

  @Test
  void anEventNamesTheUsersItReachedAndTheUserOfEachDelivery() {
    var anna = person("BASIC", "PUBLIC");
    var ben = person("MOD", "PRIVATE");
    var cleo = person("BASIC", "PRIVATE");
    TestUsers.subscribe(ben.user().id(), anna.producer().id());
    var event = publish(anna.producer(), "For Anna and Ben");

    dispatcher.dispatchPending();

    var body = deliveries(event);
    body.body("users.name", containsInAnyOrder(anna.user().name(), ben.user().name()))
        .body("users.find { it.id == '" + anna.user().id() + "' }.owner", equalTo(true))
        .body("users.find { it.id == '" + ben.user().id() + "' }.owner", equalTo(false))
        .body("users.id", not(hasItem(cleo.user().id().toString())))
        .body("items.findAll { it.userId == '" + ben.user().id() + "' }", hasSize(1))
        .body(
            "items.find { it.userId == '" + ben.user().id() + "' }.clientName",
            equalTo("traffic-phone-MOD"))
        .body(
            "items.find { it.userId == '" + ben.user().id() + "' }.userName",
            equalTo(ben.user().name()))
        .body("items.find { it.userId == '" + ben.user().id() + "' }.outcome", equalTo("DELIVERED"))
        .body("items.findAll { it.userId == '" + cleo.user().id() + "' }", empty());
  }

  @Test
  void aUsersTrafficHoldsTheirRecentEventsAndTheDeliveriesToTheirDevices() {
    var anna = person("BASIC", "PUBLIC");
    var ben = person("MOD", "PRIVATE");
    TestUsers.subscribe(ben.user().id(), anna.producer().id());
    var annas = publish(anna.producer(), "Anna's");
    var bens = publish(ben.producer(), "Ben's");
    dispatcher.dispatchPending();

    asAdmin()
        .get(TestUsers.ADMIN + "/" + ben.user().id() + "/traffic")
        .then()
        .statusCode(200)
        .body("events.id", contains(bens.toString(), annas.toString()))
        .body("deliveries.eventId", containsInAnyOrder(annas.toString(), bens.toString()))
        .body("deliveries.clientName", everyItem(equalTo("traffic-phone-MOD")))
        .body("deliveries.outcome", everyItem(equalTo("DELIVERED")))
        .body("deliveries.eventTitle", containsInAnyOrder("Ben's", "Anna's"));
    // Anna sees only her own producer's event, and its delivery to her device.
    asAdmin()
        .get(TestUsers.ADMIN + "/" + anna.user().id() + "/traffic")
        .then()
        .statusCode(200)
        .body("events.id", contains(annas.toString()))
        .body("deliveries.eventId", contains(annas.toString()));
  }

  @Test
  void aUsersTrafficIsLimitedToTheNewestAndNeedsTheAdminTokenAndAnExistingUser() {
    var anna = person("BASIC", "PRIVATE");
    for (int i = 0; i < UserTrafficResource.RECENT + 2; i++) {
      publish(anna.producer(), "Event " + i);
    }
    dispatcher.dispatchPending();

    asAdmin()
        .get(TestUsers.ADMIN + "/" + anna.user().id() + "/traffic")
        .then()
        .statusCode(200)
        .body("events", hasSize(UserTrafficResource.RECENT))
        .body("events[0].title", equalTo("Event " + (UserTrafficResource.RECENT + 1)))
        .body("deliveries", hasSize(UserTrafficResource.RECENT));
    asClient(anna.device().clientKey())
        .get(TestUsers.ADMIN + "/" + anna.user().id() + "/traffic")
        .then()
        .statusCode(401);
    io.restassured.RestAssured.given()
        .get(TestUsers.ADMIN + "/" + anna.user().id() + "/traffic")
        .then()
        .statusCode(401);
    asAdmin().get(TestUsers.ADMIN + "/" + UUID.randomUUID() + "/traffic").then().statusCode(404);
  }

  private static List<UUID> listed(UUID userId, String relation) {
    var request = asAdmin().queryParam("userId", userId.toString()).queryParam("limit", 100);
    if (relation != null) {
      request = request.queryParam("relation", relation);
    }
    List<String> ids = request.get(EVENTS).then().statusCode(200).extract().path("items.id");
    return ids.stream().map(UUID::fromString).toList();
  }

  private static io.restassured.response.ValidatableResponse deliveries(UUID eventId) {
    return asAdmin().get("/api/v1/admin/events/" + eventId + "/deliveries").then().statusCode(200);
  }

  private static UUID publish(TestProducers.Registered producer, String title) {
    return UUID.fromString(
        asProducer(producer.apiKey())
            .contentType(ContentType.JSON)
            .body(Map.of("category", "INFO", "severity", "LOW", "title", title))
            .post(EVENTS)
            .then()
            .statusCode(201)
            .extract()
            .path("id"));
  }
}
