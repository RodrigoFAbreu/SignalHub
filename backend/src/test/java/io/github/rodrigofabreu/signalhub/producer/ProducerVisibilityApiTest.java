package io.github.rodrigofabreu.signalhub.producer;

import static io.github.rodrigofabreu.signalhub.TestProducers.ADMIN;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static org.hamcrest.Matchers.contains;
import static org.hamcrest.Matchers.containsInAnyOrder;
import static org.hamcrest.Matchers.empty;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.hasKey;
import static org.hamcrest.Matchers.not;

import io.github.rodrigofabreu.signalhub.TestProducers;
import io.github.rodrigofabreu.signalhub.TestUsers;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import io.restassured.response.ValidatableResponse;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/** Who owns a producer and who sees it, through the management API, against real PostgreSQL. */
@QuarkusTest
class ProducerVisibilityApiTest {

  @Test
  void aProducerIsPrivateAndTheOwnersUnlessSaidOtherwise() {
    var plain = create(Map.of("name", "plain-" + UUID.randomUUID())).statusCode(201).extract();
    String owner = plain.path("producer.owner.id");

    asAdmin()
        .get(ADMIN + "/" + plain.<String>path("producer.id"))
        .then()
        .body("visibility", equalTo("PRIVATE"))
        .body("allowedUsers", empty())
        .body("owner.role", equalTo("ADMIN"))
        .body("owner.id", equalTo(owner));
    // The owner is subscribed to it from the start.
    asAdmin()
        .get(TestUsers.ADMIN + "/" + owner)
        .then()
        .body("subscriptions.id", org.hamcrest.Matchers.hasItem(plain.<String>path("producer.id")));
  }

  @Test
  void aProducerIsCreatedForAGivenUserWithAVisibility() {
    var user = TestUsers.create("producer-owner", "BASIC");

    var created =
        create(
                Map.of(
                    "name",
                    "owned-" + UUID.randomUUID(),
                    "ownerId",
                    user.id().toString(),
                    "visibility",
                    "PUBLIC"))
            .statusCode(201)
            .body("producer.owner.id", equalTo(user.id().toString()))
            .body("producer.owner.name", equalTo(user.name()))
            .body("producer.visibility", equalTo("PUBLIC"))
            .extract();

    asAdmin()
        .get(TestUsers.ADMIN + "/" + user.id())
        .then()
        .body("producers.id", contains(created.<String>path("producer.id")))
        .body("subscriptions.id", contains(created.<String>path("producer.id")));
  }

  @Test
  void aProducerOfAnUnknownOrRevokedUserIsRefused() {
    var gone = TestUsers.create("producer-gone", "BASIC");
    asAdmin().post(TestUsers.ADMIN + "/" + gone.id() + "/revoke").then().statusCode(200);

    create(Map.of("name", "nobody-" + UUID.randomUUID(), "ownerId", UUID.randomUUID().toString()))
        .statusCode(404);
    create(Map.of("name", "revoked-" + UUID.randomUUID(), "ownerId", gone.id().toString()))
        .statusCode(409)
        .body("title", equalTo("User is revoked"));
  }

  @ParameterizedTest
  @ValueSource(
      strings = {
        "{\"name\": \"x\", \"visibility\": \"SECRET\"}",
        "{\"name\": \"x\", \"visibility\": \"public\"}",
        "{\"name\": \"x\", \"ownerId\": \"not-a-uuid\"}",
        "{\"name\": \"x\", \"ownerId\": 5}"
      })
  void invalidCreationsAreRejected(String body) {
    asAdmin()
        .contentType(ContentType.JSON)
        .body(body)
        .post(ADMIN)
        .then()
        .statusCode(400)
        .body("title", equalTo("Invalid request"));
  }

  @Test
  void visibilityAndTheAllowListChange() {
    var owner = TestUsers.create("visibility-owner", "MOD");
    var guest = TestUsers.create("visibility-guest", "BASIC");
    var producer = TestProducers.register("visibility", owner.id(), "PRIVATE");

    update(producer.id(), Map.of("visibility", "PUBLIC"))
        .statusCode(200)
        .body("visibility", equalTo("PUBLIC"));
    update(producer.id(), Map.of("allowedUserIds", List.of(guest.id().toString())))
        .statusCode(200)
        // Changing one leaves the other.
        .body("visibility", equalTo("PUBLIC"))
        .body("allowedUsers.id", contains(guest.id().toString()))
        .body("allowedUsers.name", contains(guest.name()));
    update(producer.id(), Map.of("visibility", "PRIVATE"))
        .statusCode(200)
        .body("allowedUsers.id", contains(guest.id().toString()));
    // The owner needs no entry: it is dropped from the list.
    update(producer.id(), Map.of("allowedUserIds", List.of(owner.id().toString())))
        .statusCode(200)
        .body("allowedUsers", empty());
    asAdmin()
        .get(ADMIN)
        .then()
        .body(
            "items.find { it.id == '" + producer.id() + "' }.owner.id",
            equalTo(owner.id().toString()));
  }

  @Test
  void theAllowListNamesOnlyUsersWhoExistAndAreNotRevoked() {
    var producer = TestProducers.register("allow-list");
    var gone = TestUsers.create("allow-list-gone", "BASIC");
    asAdmin().post(TestUsers.ADMIN + "/" + gone.id() + "/revoke").then().statusCode(200);

    update(producer.id(), Map.of("allowedUserIds", List.of(UUID.randomUUID().toString())))
        .statusCode(400)
        .body("violations[0].field", equalTo("allowedUserIds"));
    update(producer.id(), Map.of("allowedUserIds", List.of(gone.id().toString()))).statusCode(400);
    asAdmin().get(ADMIN + "/" + producer.id()).then().body("allowedUsers", empty());
  }

  @ParameterizedTest
  @ValueSource(
      strings = {
        "{}",
        "{\"visibility\": null, \"allowedUserIds\": null}",
        "{\"visibility\": \"SECRET\"}",
        "{\"allowedUserIds\": \"x\"}",
        "{\"allowedUserIds\": [null]}",
        "{\"name\": \"renamed\"}",
        "not json"
      })
  void invalidChangesAreRejected(String body) {
    var producer = TestProducers.register("invalid-change");

    asAdmin()
        .contentType(ContentType.JSON)
        .body(body)
        .patch(ADMIN + "/" + producer.id())
        .then()
        .statusCode(400);

    asAdmin().get(ADMIN + "/" + producer.id()).then().body("visibility", equalTo("PRIVATE"));
  }

  @Test
  void anUnknownProducerIsNotFound() {
    update(UUID.randomUUID(), Map.of("visibility", "PUBLIC")).statusCode(404);
  }

  @Test
  void theResponsesNeverShowAKey() {
    var producer = TestProducers.register("never-a-key");

    asAdmin()
        .get(ADMIN + "/" + producer.id())
        .then()
        .body("", not(hasKey("apiKey")))
        .body("keys.id", containsInAnyOrder(producer.keyId().toString()));
  }

  @Test
  void changingWhoSeesAProducerNeedsTheAdminToken() {
    var producer = TestProducers.register("needs-token");

    io.restassured.RestAssured.given()
        .contentType(ContentType.JSON)
        .body("{\"visibility\": \"PUBLIC\"}")
        .patch(ADMIN + "/" + producer.id())
        .then()
        .statusCode(401);
    TestProducers.asProducer(producer.apiKey())
        .contentType(ContentType.JSON)
        .body("{\"visibility\": \"PUBLIC\"}")
        .patch(ADMIN + "/" + producer.id())
        .then()
        .statusCode(401);
    asAdmin().get(ADMIN + "/" + producer.id()).then().body("visibility", equalTo("PRIVATE"));
  }

  private static ValidatableResponse create(Map<String, Object> body) {
    return asAdmin().contentType(ContentType.JSON).body(body).post(ADMIN).then();
  }

  private static ValidatableResponse update(UUID id, Map<String, Object> body) {
    return asAdmin().contentType(ContentType.JSON).body(body).patch(ADMIN + "/" + id).then();
  }
}
