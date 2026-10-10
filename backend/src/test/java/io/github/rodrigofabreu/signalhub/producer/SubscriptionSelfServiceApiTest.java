package io.github.rodrigofabreu.signalhub.producer;

import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.producer.OwnProducerApiTest.create;
import static io.github.rodrigofabreu.signalhub.producer.OwnProducerApiTest.patch;
import static io.github.rodrigofabreu.signalhub.producer.OwnProducerApiTest.post;
import static io.github.rodrigofabreu.signalhub.producer.OwnProducerApiTest.publish;
import static io.github.rodrigofabreu.signalhub.producer.OwnProducerApiTest.unique;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.contains;
import static org.hamcrest.Matchers.containsInAnyOrder;
import static org.hamcrest.Matchers.empty;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.not;

import io.github.rodrigofabreu.signalhub.TestClients;
import io.github.rodrigofabreu.signalhub.TestClients.Registered;
import io.quarkus.test.junit.QuarkusTest;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/**
 * Who sees which producer from a device, subscribing, and how changing visibility or the allow-list
 * changes what a user receives, against real PostgreSQL.
 */
@QuarkusTest
class SubscriptionSelfServiceApiTest {

  private static final String PRODUCERS = "/api/v1/client/producers";
  private static final String VISIBLE = "/api/v1/client/visible-producers";
  private static final String EVENTS = "/api/v1/events";

  /** A created producer: its ID, name and key. */
  private record Made(String id, String name, String key) {}

  private static Made make(Registered owner, String visibility) {
    var name = unique("sub");
    var created = create(owner, Map.of("name", name, "visibility", visibility)).statusCode(201);
    return new Made(
        created.extract().path("producer.id"), name, created.extract().<String>path("apiKey"));
  }

  private static List<String> visibleIds(Registered user) {
    return asClient(user.clientKey())
        .get(VISIBLE)
        .then()
        .statusCode(200)
        .extract()
        .path("items.id");
  }

  private static List<String> inboxTitles(Registered user) {
    return asClient(user.clientKey())
        .queryParam("limit", 100)
        .get(EVENTS)
        .then()
        .statusCode(200)
        .extract()
        .path("items.title");
  }

  private static void subscribe(Registered user, String id, int status) {
    asClient(user.clientKey()).put(VISIBLE + "/" + id + "/subscription").then().statusCode(status);
  }

  @ParameterizedTest
  @ValueSource(strings = {"BASIC", "MOD", "ADMIN"})
  void everyRoleSeesPublicOwnAndAllowedProducersAndNoOthers(String role) {
    var viewer = TestClients.registerAs(role, "visible-" + role);
    var other = TestClients.registerAs("BASIC", "visible-other");
    var publics = make(other, "PUBLIC");
    var privates = make(other, "PRIVATE");
    var allowed = make(other, "PRIVATE");
    var mine = make(viewer, "PRIVATE");
    asClient(other.clientKey())
        .put(PRODUCERS + "/" + allowed.id() + "/allowed-users/" + viewer.userId())
        .then()
        .statusCode(200);

    var ids = visibleIds(viewer);
    org.junit.jupiter.api.Assertions.assertTrue(
        ids.containsAll(List.of(publics.id(), allowed.id(), mine.id())));
    org.junit.jupiter.api.Assertions.assertFalse(ids.contains(privates.id()));

    // The owner's name, not their role, keys or allow-list.
    var shown =
        asClient(viewer.clientKey())
            .get(VISIBLE)
            .then()
            .body(
                "items.find { it.id == '" + publics.id() + "' }.owner.id",
                equalTo(other.userId().toString()))
            .body("items.find { it.id == '" + publics.id() + "' }.subscribed", equalTo(false))
            .body("items.find { it.id == '" + mine.id() + "' }.subscribed", equalTo(true))
            .extract()
            .asString();
    org.junit.jupiter.api.Assertions.assertFalse(shown.contains("role"));
    org.junit.jupiter.api.Assertions.assertFalse(shown.contains("shpk1_"));
    org.junit.jupiter.api.Assertions.assertFalse(shown.contains("allowedUsers"));

    // A private producer of someone else's cannot be subscribed to, and looks like a missing one.
    subscribe(viewer, privates.id(), 404);
    subscribe(viewer, UUID.randomUUID().toString(), 404);
    asClient(viewer.clientKey())
        .delete(VISIBLE + "/" + privates.id() + "/subscription")
        .then()
        .statusCode(404);
    asClient(other.clientKey())
        .get(VISIBLE)
        .then()
        .body("items.find { it.id == '" + privates.id() + "' }.subscribed", equalTo(true));
  }

  @Test
  void aSecondUserSubscribesToAPublicProducerAndReceivesItsEvents() {
    var owner = TestClients.registerAs("BASIC", "flow-owner");
    var fan = TestClients.registerAs("BASIC", "flow-fan");
    var producer = make(owner, "PRIVATE");

    // Private: the fan sees and receives nothing.
    publish(producer.key(), "before-public");
    org.junit.jupiter.api.Assertions.assertFalse(visibleIds(fan).contains(producer.id()));
    subscribe(fan, producer.id(), 404);

    // The owner makes it public; the fan subscribes and finds its stored and new events.
    patch(owner, PRODUCERS + "/" + producer.id(), Map.of("visibility", "PUBLIC")).statusCode(200);
    asClient(fan.clientKey())
        .put(VISIBLE + "/" + producer.id() + "/subscription")
        .then()
        .statusCode(200)
        .body("subscribed", equalTo(true))
        .body("owner.id", equalTo(owner.userId().toString()))
        .body("owner.name", org.hamcrest.Matchers.notNullValue());
    subscribe(fan, producer.id(), 200);
    publish(producer.key(), "after-public");
    org.hamcrest.MatcherAssert.assertThat(
        inboxTitles(fan), containsInAnyOrder("before-public", "after-public"));

    // Unsubscribing stops them; it is idempotent.
    asClient(fan.clientKey())
        .delete(VISIBLE + "/" + producer.id() + "/subscription")
        .then()
        .statusCode(200)
        .body("subscribed", equalTo(false));
    asClient(fan.clientKey())
        .delete(VISIBLE + "/" + producer.id() + "/subscription")
        .then()
        .statusCode(200);
    publish(producer.key(), "unseen");
    org.hamcrest.MatcherAssert.assertThat(inboxTitles(fan), empty());
  }

  @Test
  void makingAProducerPrivateEndsTheSubscriptionsOfThoseWhoNoLongerSeeIt() {
    var owner = TestClients.registerAs("MOD", "private-owner");
    var allowedFan = TestClients.registerAs("BASIC", "private-allowed");
    var fan = TestClients.registerAs("BASIC", "private-fan");
    var producer = make(owner, "PUBLIC");
    subscribe(allowedFan, producer.id(), 200);
    subscribe(fan, producer.id(), 200);
    asClient(owner.clientKey())
        .put(PRODUCERS + "/" + producer.id() + "/allowed-users/" + allowedFan.userId())
        .then()
        .statusCode(200);

    patch(owner, PRODUCERS + "/" + producer.id(), Map.of("visibility", "PRIVATE")).statusCode(200);
    publish(producer.key(), "after-private");

    org.hamcrest.MatcherAssert.assertThat(inboxTitles(allowedFan), contains("after-private"));
    org.hamcrest.MatcherAssert.assertThat(inboxTitles(fan), empty());
    org.junit.jupiter.api.Assertions.assertFalse(visibleIds(fan).contains(producer.id()));
    // The producer's events are not found by ID either.
    var eventId = publish(producer.key(), "secret");
    asClient(fan.clientKey()).get(EVENTS + "/" + eventId).then().statusCode(404);
    // Public again changes nobody's subscription: the fan must subscribe again.
    patch(owner, PRODUCERS + "/" + producer.id(), Map.of("visibility", "PUBLIC")).statusCode(200);
    org.hamcrest.MatcherAssert.assertThat(
        asClient(fan.clientKey())
            .get(VISIBLE)
            .then()
            .extract()
            .<List<String>>path("items.findAll { it.subscribed }.id"),
        not(hasItem(producer.id())));
  }

  @Test
  void theAllowListAddsAndRemovesUsersAndSubscriptionsFollow() {
    var owner = TestClients.registerAs("BASIC", "allow-owner");
    var guest = TestClients.registerAs("BASIC", "allow-guest");
    var producer = make(owner, "PRIVATE");
    var url = PRODUCERS + "/" + producer.id() + "/allowed-users/" + guest.userId();

    asClient(owner.clientKey())
        .put(url)
        .then()
        .statusCode(200)
        .body("allowedUsers.id", contains(guest.userId().toString()))
        .body("allowedUsers[0].name", org.hamcrest.Matchers.notNullValue())
        .body("allowedUsers[0]", not(org.hamcrest.Matchers.hasKey("role")));
    // Allowing twice, or the owner, changes nothing.
    asClient(owner.clientKey())
        .put(url)
        .then()
        .statusCode(200)
        .body("allowedUsers", org.hamcrest.Matchers.hasSize(1));
    asClient(owner.clientKey())
        .put(PRODUCERS + "/" + producer.id() + "/allowed-users/" + owner.userId())
        .then()
        .statusCode(200)
        .body("allowedUsers", org.hamcrest.Matchers.hasSize(1));
    // An unknown user, or a revoked one, cannot be allowed.
    asClient(owner.clientKey())
        .put(PRODUCERS + "/" + producer.id() + "/allowed-users/" + UUID.randomUUID())
        .then()
        .statusCode(404);
    var gone = TestClients.registerAs("BASIC", "allow-gone");
    given()
        .header(
            "Authorization",
            "Bearer " + io.github.rodrigofabreu.signalhub.TestProducers.adminToken())
        .post("/api/v1/admin/users/" + gone.userId() + "/revoke")
        .then()
        .statusCode(200);
    asClient(owner.clientKey())
        .put(PRODUCERS + "/" + producer.id() + "/allowed-users/" + gone.userId())
        .then()
        .statusCode(404);

    // Allowed, the guest sees it and subscribes; taking them off ends the subscription.
    subscribe(guest, producer.id(), 200);
    publish(producer.key(), "for-guest");
    org.hamcrest.MatcherAssert.assertThat(inboxTitles(guest), contains("for-guest"));
    asClient(owner.clientKey()).delete(url).then().statusCode(200).body("allowedUsers", empty());
    asClient(owner.clientKey()).delete(url).then().statusCode(200);
    publish(producer.key(), "after-removal");
    org.hamcrest.MatcherAssert.assertThat(inboxTitles(guest), empty());
    subscribe(guest, producer.id(), 404);

    // The owner cannot be taken off their own producer by removing themselves.
    asClient(owner.clientKey())
        .delete(PRODUCERS + "/" + producer.id() + "/allowed-users/" + owner.userId())
        .then()
        .statusCode(200)
        .body("subscribed", equalTo(true));
  }

  @Test
  void aGuestCannotChangeTheAllowListOrVisibilityOfAProducerTheyOnlySee() {
    var owner = TestClients.registerAs("BASIC", "guest-owner");
    var guest = TestClients.registerAs("MOD", "guest-mod");
    var producer = make(owner, "PUBLIC");
    asClient(guest.clientKey())
        .put(PRODUCERS + "/" + producer.id() + "/allowed-users/" + guest.userId())
        .then()
        .statusCode(404);
    patch(guest, PRODUCERS + "/" + producer.id(), Map.of("visibility", "PRIVATE")).statusCode(404);
    post(guest, PRODUCERS + "/" + producer.id() + "/disable").statusCode(404);
  }

  @Test
  void anOwnerMayUnsubscribeFromTheirOwnProducerAndSubscribeAgain() {
    var owner = TestClients.registerAs("BASIC", "self-sub");
    var producer = make(owner, "PRIVATE");
    asClient(owner.clientKey())
        .delete(VISIBLE + "/" + producer.id() + "/subscription")
        .then()
        .statusCode(200);
    publish(producer.key(), "muted");
    org.hamcrest.MatcherAssert.assertThat(inboxTitles(owner), empty());
    subscribe(owner, producer.id(), 200);
    org.hamcrest.MatcherAssert.assertThat(inboxTitles(owner), contains("muted"));
  }
}
