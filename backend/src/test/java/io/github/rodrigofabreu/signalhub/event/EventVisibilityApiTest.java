package io.github.rodrigofabreu.signalhub.event;

import static io.github.rodrigofabreu.signalhub.TestClients.CLIENT;
import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.github.rodrigofabreu.signalhub.TestProducers.asProducer;
import static org.hamcrest.Matchers.containsInAnyOrder;
import static org.hamcrest.Matchers.empty;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.not;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.github.rodrigofabreu.signalhub.TestClients;
import io.github.rodrigofabreu.signalhub.TestClients.Registered;
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
 * Who receives which event: a user gets, in the inbox, the unread count, by ID and by push, only
 * the events of the producers they are subscribed to, and everyone else's are not found. Read state
 * is the user's. The operator, with the admin token, sees every event. Against real PostgreSQL,
 * with the fake push provider.
 */
@QuarkusTest
class EventVisibilityApiTest {

  private static final String EVENTS = "/api/v1/events";

  @Inject EventPushDispatcher dispatcher;
  @Inject FakePushProvider fake;

  @BeforeEach
  void setUp() {
    // Events from other tests wait in the outbox too; send them before each test's own.
    dispatcher.dispatchPending();
    fake.answer((token, message) -> PushOutcome.delivered());
  }

  /** A user with one device, a push target and a private producer of their own. */
  private record Person(
      TestUsers.Created user, Registered device, String token, TestProducers.Registered producer) {}

  private static Person person(String role) {
    var user = TestUsers.create("visibility-" + role, role);
    var device = TestClients.registerFor(user.id(), "device-" + role);
    var token = "visibility-" + UUID.randomUUID();
    asClient(device.clientKey())
        .contentType(ContentType.JSON)
        .body(Map.of("provider", FakePushProvider.NAME, "token", token))
        .put(CLIENT + "/push-target")
        .then()
        .statusCode(200);
    return new Person(
        user, device, token, TestProducers.register("visibility", user.id(), "PRIVATE"));
  }

  @Test
  void aUserListsOnlyTheEventsOfTheirSubscriptions() {
    var anna = person("BASIC");
    var ben = person("MOD");
    var owners = TestProducers.register("visibility-owners");
    var annas = publish(anna.producer(), "Anna's");
    var bens = publish(ben.producer(), "Ben's");
    var owner = publish(owners, "Owner's");

    assertEquals(List.of(annas), idsOf(anna.device()));
    assertEquals(List.of(bens), idsOf(ben.device()));
    // Filtering by a producer the user does not see finds nothing, rather than the producer.
    asClient(anna.device().clientKey())
        .queryParam("producerId", ben.producer().id().toString())
        .get(EVENTS)
        .then()
        .statusCode(200)
        .body("items", empty());
    // The operator sees every event.
    asAdmin()
        .queryParam("limit", 100)
        .get(EVENTS)
        .then()
        .body("items.id", hasItem(annas.toString()))
        .body("items.id", hasItem(bens.toString()))
        .body("items.id", hasItem(owner.toString()));
  }

  @Test
  void anEventOfAProducerTheUserIsNotSubscribedToIsNotFoundWhateverIsDoneWithIt() {
    var anna = person("BASIC");
    var ben = person("BASIC");
    var secret = publish(ben.producer(), "Ben's secret");
    var annas = anna.device().clientKey();

    asClient(annas).get(EVENTS + "/" + secret).then().statusCode(404);
    asClient(annas).put(EVENTS + "/" + secret + "/read").then().statusCode(404);
    asClient(annas).delete(EVENTS + "/" + secret + "/read").then().statusCode(404);
    asClient(annas)
        .contentType(ContentType.JSON)
        .body("{\"through\": \"" + secret + "\"}")
        .post(EVENTS + "/read")
        .then()
        .statusCode(404);
    // The same answer as for an event that does not exist.
    asClient(annas).get(EVENTS + "/" + UUID.randomUUID()).then().statusCode(404);
    // Nothing of it reached Ben's own read state or the operator's.
    asClient(ben.device().clientKey())
        .get(EVENTS + "/" + secret)
        .then()
        .statusCode(200)
        .body("readAt", org.hamcrest.Matchers.nullValue());
    asAdmin().get(EVENTS + "/" + secret).then().statusCode(200);
  }

  @Test
  void theUnreadCountCountsOnlyTheEventsTheUserReceives() {
    var anna = person("MOD");
    var ben = person("MOD");
    publish(anna.producer(), "One");
    publish(anna.producer(), "Two");
    publish(ben.producer(), "Not Anna's");

    assertEquals(2, unread(anna.device()));
    assertEquals(1, unread(ben.device()));
  }

  @Test
  void markingReadThroughAnEventDoesNotReachEventsTheUserDoesNotReceive() {
    var anna = person("MOD");
    var ben = person("MOD");
    var first = publish(anna.producer(), "Anna's first");
    var bens = publish(ben.producer(), "Ben's, in between");
    var last = publish(anna.producer(), "Anna's last");

    asClient(anna.device().clientKey())
        .contentType(ContentType.JSON)
        .body("{\"through\": \"" + last + "\"}")
        .post(EVENTS + "/read")
        .then()
        .statusCode(200)
        .body("marked", equalTo(2));

    assertEquals(0, unread(anna.device()));
    assertEquals(1, unread(ben.device()));
    asClient(ben.device().clientKey())
        .get(EVENTS + "/" + bens)
        .then()
        .body("readAt", org.hamcrest.Matchers.nullValue());
    assertEquals(List.of(last, first), idsOf(anna.device()));
  }

  @Test
  void subscribingToAPublicProducerGivesItsEventsAndUnsubscribingTakesThemAway() {
    var anna = person("BASIC");
    var publicProducer = TestProducers.registerPublic("visibility-public");
    var before = publish(publicProducer, "Published before");
    assertEquals(List.of(), idsOf(anna.device()));

    TestUsers.subscribe(anna.user().id(), publicProducer.id());
    var after = publish(publicProducer, "Published after");

    assertEquals(List.of(after, before), idsOf(anna.device()));
    asClient(anna.device().clientKey()).get(EVENTS + "/" + before).then().statusCode(200);

    asAdmin()
        .delete(TestUsers.ADMIN + "/" + anna.user().id() + "/subscriptions/" + publicProducer.id())
        .then()
        .statusCode(200);
    assertEquals(List.of(), idsOf(anna.device()));
    asClient(anna.device().clientKey()).get(EVENTS + "/" + after).then().statusCode(404);
    assertEquals(0, unread(anna.device()));
  }

  @Test
  void anEventIsPushedOnlyToTheDevicesOfTheUsersSubscribedToItsProducer() {
    var anna = person("BASIC");
    var ben = person("MOD");
    var cleo = person("BASIC");
    var annasSecond = TestClients.registerFor(anna.user().id(), "Anna's tablet");
    var secondToken = "visibility-" + UUID.randomUUID();
    asClient(annasSecond.clientKey())
        .contentType(ContentType.JSON)
        .body(Map.of("provider", FakePushProvider.NAME, "token", secondToken))
        .put(CLIENT + "/push-target")
        .then()
        .statusCode(200);
    var publicProducer = TestProducers.registerPublic("visibility-push-public");
    TestUsers.subscribe(ben.user().id(), publicProducer.id());

    var annas = publish(anna.producer(), "For Anna only");
    var shared = publish(publicProducer, "For subscribers");
    dispatcher.dispatchPending();

    // Every device of the subscribed user, and no one else's.
    assertEquals(
        List.of(anna.token(), secondToken), recipientsOf(annas, anna.token(), secondToken));
    assertEquals(List.of(), recipientsOf(annas, ben.token(), cleo.token()));
    assertEquals(
        List.of(ben.token()), recipientsOf(shared, anna.token(), ben.token(), cleo.token()));
  }

  @Test
  void aUserWhoSeesAProducerOnlyThroughTheAllowListLosesItWhenTakenOff() {
    var anna = person("BASIC");
    var ben = person("BASIC");
    var annas = anna.producer();
    asAdmin()
        .contentType(ContentType.JSON)
        .body(Map.of("allowedUserIds", List.of(ben.user().id().toString())))
        .patch(TestProducers.ADMIN + "/" + annas.id())
        .then()
        .statusCode(200);
    TestUsers.subscribe(ben.user().id(), annas.id());
    var visible = publish(annas, "Shared with Ben");
    dispatcher.dispatchPending();
    assertEquals(List.of(visible), idsOf(ben.device()));
    assertEquals(List.of(ben.token()), recipientsOf(visible, ben.token()));

    asAdmin()
        .contentType(ContentType.JSON)
        .body(Map.of("allowedUserIds", List.of()))
        .patch(TestProducers.ADMIN + "/" + annas.id())
        .then()
        .statusCode(200);

    // Losing sight of a private producer ends the subscription: nothing listed, nothing pushed.
    assertEquals(List.of(), idsOf(ben.device()));
    asClient(ben.device().clientKey()).get(EVENTS + "/" + visible).then().statusCode(404);
    var hidden = publish(annas, "Hidden from Ben");
    dispatcher.dispatchPending();
    assertEquals(List.of(), recipientsOf(hidden, ben.token()));
    assertEquals(List.of(anna.token()), recipientsOf(hidden, anna.token(), ben.token()));
  }

  @Test
  void makingAPublicProducerPrivateEndsTheSubscriptionsOfThoseWhoCannotSeeIt() {
    var anna = person("BASIC");
    var ben = person("BASIC");
    var cleo = person("BASIC");
    var shared = TestProducers.register("visibility-turning-private", anna.user().id(), "PUBLIC");
    TestUsers.subscribe(ben.user().id(), shared.id());
    TestUsers.subscribe(cleo.user().id(), shared.id());
    asAdmin()
        .contentType(ContentType.JSON)
        .body(Map.of("allowedUserIds", List.of(cleo.user().id().toString())))
        .patch(TestProducers.ADMIN + "/" + shared.id())
        .then()
        .statusCode(200);
    var event = publish(shared, "Before it turns private");
    assertEquals(List.of(event), idsOf(ben.device()));

    asAdmin()
        .contentType(ContentType.JSON)
        .body(Map.of("visibility", "PRIVATE"))
        .patch(TestProducers.ADMIN + "/" + shared.id())
        .then()
        .statusCode(200);

    // Its owner and the user on its allow-list keep it; the one who was neither does not.
    assertEquals(List.of(), idsOf(ben.device()));
    assertEquals(List.of(event), idsOf(cleo.device()));
    assertEquals(List.of(event), idsOf(anna.device()));
  }

  @Test
  void aRevokedUserLosesTheirDevicesAndProducersButTheirEventsStay() {
    var anna = person("MOD");
    var event = publish(anna.producer(), "Anna's, before");

    asAdmin().post(TestUsers.ADMIN + "/" + anna.user().id() + "/revoke").then().statusCode(200);

    asClient(anna.device().clientKey()).get(EVENTS).then().statusCode(401);
    // Their producers' keys stop working too.
    asProducer(anna.producer().apiKey())
        .contentType(ContentType.JSON)
        .body(Map.of("category", "INFO", "severity", "LOW", "title", "After"))
        .post(EVENTS)
        .then()
        .statusCode(401);
    // The events stay for the operator, who may delete them with the existing deletion.
    asAdmin().get(EVENTS + "/" + event).then().statusCode(200);
    dispatcher.dispatchPending();
    assertEquals(List.of(), recipientsOf(event, anna.token()));
  }

  @Test
  void theOperatorSeesEveryEventAndHasAReadStateOfTheirOwn() {
    var anna = person("BASIC");
    var event = publish(anna.producer(), "Seen by the operator");

    asAdmin().put(EVENTS + "/" + event + "/read").then().statusCode(200);

    asAdmin()
        .get(EVENTS + "/" + event)
        .then()
        .body("readAt", not(org.hamcrest.Matchers.nullValue()));
    // Not Anna's.
    asClient(anna.device().clientKey())
        .get(EVENTS + "/" + event)
        .then()
        .body("readAt", org.hamcrest.Matchers.nullValue());
    assertEquals(1, unread(anna.device()));
    asAdmin()
        .queryParam("producerId", anna.producer().id().toString())
        .queryParam("read", "false")
        .get(EVENTS)
        .then()
        .body("items", empty());
    asClient(anna.device().clientKey())
        .queryParam("read", "false")
        .get(EVENTS)
        .then()
        .body("items.id", containsInAnyOrder(event.toString()));
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

  /** The IDs of the events the device's user receives, newest first. */
  private static List<UUID> idsOf(Registered device) {
    List<String> ids =
        asClient(device.clientKey())
            .queryParam("limit", 100)
            .get(EVENTS)
            .then()
            .statusCode(200)
            .extract()
            .path("items.id");
    return ids.stream().map(UUID::fromString).toList();
  }

  private static int unread(Registered device) {
    return asClient(device.clientKey())
        .get(EVENTS + "/unread-count")
        .then()
        .statusCode(200)
        .extract()
        .path("unread");
  }

  /** Which of the given push targets received the event, in the order given. */
  private List<String> recipientsOf(UUID eventId, String... tokens) {
    return java.util.Arrays.stream(tokens)
        .filter(
            token ->
                fake.sent().stream()
                    .anyMatch(
                        sent ->
                            sent.token().equals(token)
                                && eventId.toString().equals(sent.message().data().get("eventId"))))
        .toList();
  }

  @Test
  void aProducerWithNoSubscribersStillStoresItsEvents() {
    // Subscribing is how a user receives events, not how a producer publishes them.
    var anna = person("BASIC");
    asClient(anna.device().clientKey()).get(EVENTS).then().statusCode(200);
    asAdmin()
        .delete(TestUsers.ADMIN + "/" + anna.user().id() + "/subscriptions/" + anna.producer().id())
        .then()
        .statusCode(200);

    var event = publish(anna.producer(), "Nobody listening");
    dispatcher.dispatchPending();

    asAdmin().get(EVENTS + "/" + event).then().statusCode(200);
    assertEquals(List.of(), idsOf(anna.device()));
    assertTrue(recipientsOf(event, anna.token()).isEmpty());
  }
}
