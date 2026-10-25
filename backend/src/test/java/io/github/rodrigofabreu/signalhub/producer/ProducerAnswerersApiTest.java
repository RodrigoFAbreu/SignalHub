package io.github.rodrigofabreu.signalhub.producer;

import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.contains;
import static org.hamcrest.Matchers.empty;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.not;
import static org.junit.jupiter.api.Assertions.assertEquals;

import io.github.rodrigofabreu.signalhub.TestClients;
import io.github.rodrigofabreu.signalhub.TestProducers;
import io.github.rodrigofabreu.signalhub.TestUsers;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import io.restassured.response.ValidatableResponse;
import java.util.UUID;
import org.junit.jupiter.api.Test;

/**
 * The users who may answer a producer's questions: named by its owner from a device, read-only to
 * the operator, and ended whenever they lose sight of the producer or are revoked.
 */
@QuarkusTest
class ProducerAnswerersApiTest {

  private static final String PRODUCERS = "/api/v1/client/producers";

  /** A private producer owned by a MOD, the owner's device, and an invited user to name. */
  private record Scene(
      TestProducers.Registered producer,
      TestClients.Registered owner,
      TestUsers.Created ana,
      TestClients.Registered anaDevice) {
    String answerer() {
      return PRODUCERS + "/" + producer.id() + "/answerers/" + ana.id();
    }
  }

  private static Scene scene(String visibility) {
    var ownerUser = TestUsers.create("answerers-owner", "MOD");
    var producer = TestProducers.register("answerers", ownerUser.id(), visibility);
    var owner = TestClients.registerFor(ownerUser.id(), "answerers-owner-phone");
    var ana = TestUsers.create("answerers-ana", "BASIC");
    var anaDevice = TestClients.registerFor(ana.id(), "answerers-ana-phone");
    return new Scene(producer, owner, ana, anaDevice);
  }

  private static ValidatableResponse allow(Scene scene) {
    return asClient(scene.owner().clientKey())
        .put(PRODUCERS + "/" + scene.producer().id() + "/allowed-users/" + scene.ana().id())
        .then();
  }

  private static ValidatableResponse nameAnswerer(Scene scene) {
    return asClient(scene.owner().clientKey()).put(scene.answerer()).then();
  }

  private static ValidatableResponse ownProducer(Scene scene) {
    return asClient(scene.owner().clientKey())
        .get(PRODUCERS + "/" + scene.producer().id())
        .then()
        .statusCode(200);
  }

  private static Object canAnswer(Scene scene, TestClients.Registered device) {
    return asClient(device.clientKey())
        .get("/api/v1/client/visible-producers")
        .then()
        .statusCode(200)
        .extract()
        .path("items.find { it.id == '" + scene.producer().id() + "' }.canAnswer");
  }

  @Test
  void theVisibleProducersSayWhetherTheCallerMayAnswerThem() {
    var scene = scene("PUBLIC");

    assertEquals(true, canAnswer(scene, scene.owner()));
    assertEquals(false, canAnswer(scene, scene.anaDevice()));

    nameAnswerer(scene).statusCode(200);
    assertEquals(true, canAnswer(scene, scene.anaDevice()));
  }

  @Test
  void aNewProducerHasNoAnswerers() {
    var scene = scene("PRIVATE");

    ownProducer(scene).body("answerers", empty());
    asAdmin()
        .get(TestProducers.ADMIN + "/" + scene.producer().id())
        .then()
        .body("answerers", empty());
  }

  @Test
  void theOwnerNamesAnAnswererWhoSeesTheProducerAndTheyAreListedByName() {
    var scene = scene("PRIVATE");
    allow(scene).statusCode(200);

    nameAnswerer(scene)
        .statusCode(200)
        .body("answerers.id", contains(scene.ana().id().toString()))
        .body("answerers.name", contains(scene.ana().name()))
        // Never their role: the owner sees names only.
        .body("answerers[0].role", org.hamcrest.Matchers.nullValue());
    ownProducer(scene).body("answerers.id", contains(scene.ana().id().toString()));
    // The operator sees them, read-only.
    asAdmin()
        .get(TestProducers.ADMIN + "/" + scene.producer().id())
        .then()
        .body("answerers.id", contains(scene.ana().id().toString()))
        .body("answerers[0].role", equalTo("BASIC"));
    asAdmin()
        .get(TestProducers.ADMIN)
        .then()
        .body(
            "items.find { it.id == '" + scene.producer().id() + "' }.answerers.name",
            contains(scene.ana().name()));
  }

  @Test
  void namingAnAnswererTwiceOrNamingTheOwnerChangesNothing() {
    var scene = scene("PRIVATE");
    allow(scene).statusCode(200);

    nameAnswerer(scene).statusCode(200);
    nameAnswerer(scene).statusCode(200).body("answerers", org.hamcrest.Matchers.hasSize(1));
    asClient(scene.owner().clientKey())
        .put(PRODUCERS + "/" + scene.producer().id() + "/answerers/" + scene.owner().userId())
        .then()
        .statusCode(200)
        .body("answerers", org.hamcrest.Matchers.hasSize(1));
  }

  @Test
  void aUserWhoCannotSeeTheProducerCannotBeNamedButAnyUserCanOnAPublicOne() {
    var privateScene = scene("PRIVATE");
    nameAnswerer(privateScene).statusCode(409);
    ownProducer(privateScene).body("answerers", empty());

    var publicScene = scene("PUBLIC");
    nameAnswerer(publicScene).statusCode(200);
  }

  @Test
  void anUnknownOrRevokedUserIsNotFound() {
    var scene = scene("PUBLIC");

    asClient(scene.owner().clientKey())
        .put(PRODUCERS + "/" + scene.producer().id() + "/answerers/" + UUID.randomUUID())
        .then()
        .statusCode(404);
    var gone = TestUsers.create("answerers-gone", "BASIC");
    asAdmin().post(TestUsers.ADMIN + "/" + gone.id() + "/revoke").then().statusCode(200);
    asClient(scene.owner().clientKey())
        .put(PRODUCERS + "/" + scene.producer().id() + "/answerers/" + gone.id())
        .then()
        .statusCode(404);
  }

  @Test
  void onlyTheOwnerManagesAnswerersAndAnotherUsersProducerIsNotFound() {
    var scene = scene("PUBLIC");

    asClient(scene.anaDevice().clientKey()).put(scene.answerer()).then().statusCode(404);
    asClient(scene.anaDevice().clientKey()).delete(scene.answerer()).then().statusCode(404);
    given().put(scene.answerer()).then().statusCode(401);
    asAdmin().put(scene.answerer()).then().statusCode(401);
  }

  @Test
  void removingAnAnswererWhoIsNotOneChangesNothing() {
    var scene = scene("PUBLIC");
    nameAnswerer(scene).statusCode(200);

    asClient(scene.owner().clientKey())
        .delete(scene.answerer())
        .then()
        .statusCode(200)
        .body("answerers", empty());
    asClient(scene.owner().clientKey()).delete(scene.answerer()).then().statusCode(200);
  }

  @Test
  void anAnswererLeavesWhenTheyAreTakenOffTheAllowListByTheOwner() {
    var scene = scene("PRIVATE");
    allow(scene).statusCode(200);
    nameAnswerer(scene).statusCode(200);

    asClient(scene.owner().clientKey())
        .delete(PRODUCERS + "/" + scene.producer().id() + "/allowed-users/" + scene.ana().id())
        .then()
        .statusCode(200)
        .body("answerers", empty());
  }

  @Test
  void anAnswererLeavesWhenTheOperatorReplacesTheAllowList() {
    var scene = scene("PRIVATE");
    allow(scene).statusCode(200);
    nameAnswerer(scene).statusCode(200);

    asAdmin()
        .contentType(ContentType.JSON)
        .body("{\"allowedUserIds\": []}")
        .patch(TestProducers.ADMIN + "/" + scene.producer().id())
        .then()
        .statusCode(200)
        .body("answerers", empty());
    ownProducer(scene).body("answerers", empty());
  }

  @Test
  void anAnswererWhoSeesTheProducerAnywayStaysWhenItIsMadePrivate() {
    var scene = scene("PUBLIC");
    nameAnswerer(scene).statusCode(200);
    // On the allow-list: made private, they still see it, so they still answer.
    allow(scene).statusCode(200);

    asClient(scene.owner().clientKey())
        .contentType(ContentType.JSON)
        .body("{\"visibility\": \"PRIVATE\"}")
        .patch(PRODUCERS + "/" + scene.producer().id())
        .then()
        .statusCode(200)
        .body("answerers.id", contains(scene.ana().id().toString()));
  }

  @Test
  void anAnswererLeavesWhenTheOwnerMakesTheProducerPrivate() {
    var scene = scene("PUBLIC");
    nameAnswerer(scene).statusCode(200);

    asClient(scene.owner().clientKey())
        .contentType(ContentType.JSON)
        .body("{\"visibility\": \"PRIVATE\"}")
        .patch(PRODUCERS + "/" + scene.producer().id())
        .then()
        .statusCode(200)
        .body("answerers", empty());
  }

  @Test
  void anAnswererLeavesWhenTheOperatorMakesTheProducerPrivate() {
    var scene = scene("PUBLIC");
    nameAnswerer(scene).statusCode(200);

    asAdmin()
        .contentType(ContentType.JSON)
        .body("{\"visibility\": \"PRIVATE\"}")
        .patch(TestProducers.ADMIN + "/" + scene.producer().id())
        .then()
        .statusCode(200)
        .body("answerers", empty());
  }

  @Test
  void anAnswererLeavesEveryProducerWhenTheyAreRevoked() {
    var first = scene("PUBLIC");
    var secondProducer =
        TestProducers.register("answerers-second", first.owner().userId(), "PUBLIC");
    nameAnswerer(first).statusCode(200);
    asClient(first.owner().clientKey())
        .put(PRODUCERS + "/" + secondProducer.id() + "/answerers/" + first.ana().id())
        .then()
        .statusCode(200);

    asAdmin().post(TestUsers.ADMIN + "/" + first.ana().id() + "/revoke").then().statusCode(200);

    ownProducer(first).body("answerers", empty());
    asClient(first.owner().clientKey())
        .get(PRODUCERS + "/" + secondProducer.id())
        .then()
        .body("answerers", empty());
  }

  @Test
  void theAdminApiAcceptsNoAnswerersField() {
    var scene = scene("PUBLIC");

    asAdmin()
        .contentType(ContentType.JSON)
        .body("{\"answerers\": []}")
        .patch(TestProducers.ADMIN + "/" + scene.producer().id())
        .then()
        .statusCode(400)
        .body("violations.field", hasItem("answerers"));
    asAdmin()
        .contentType(ContentType.JSON)
        .body("{\"name\": \"answerers-x-" + UUID.randomUUID() + "\", \"answerers\": []}")
        .post(TestProducers.ADMIN)
        .then()
        .statusCode(400);
  }

  @Test
  void anAnswererAnswersOnlyWhileTheyAreOne() {
    var scene = scene("PUBLIC");
    TestUsers.subscribe(scene.ana().id(), scene.producer().id());
    var event =
        TestProducers.asProducer(scene.producer().apiKey())
            .contentType(ContentType.JSON)
            .body(
                """
                {"category": "ACTION_REQUIRED", "severity": "HIGH", "title": "Merge it?",
                 "ask": {"choices": [{"id": "merge", "label": "Merge"}]}}
                """)
            .post("/api/v1/events")
            .then()
            .statusCode(201)
            .extract()
            .<String>path("id");
    var answer = "/api/v1/events/" + event + "/answer";

    asClient(scene.anaDevice().clientKey())
        .contentType(ContentType.JSON)
        .body("{\"choices\": [\"merge\"]}")
        .put(answer)
        .then()
        .statusCode(403);
    nameAnswerer(scene).statusCode(200);
    asClient(scene.anaDevice().clientKey())
        .get("/api/v1/events/" + event)
        .then()
        .body("canAnswer", equalTo(true));
    asClient(scene.owner().clientKey()).delete(scene.answerer()).then().statusCode(200);
    asClient(scene.anaDevice().clientKey())
        .get("/api/v1/events/" + event)
        .then()
        .body("canAnswer", equalTo(false))
        .body("ask.whoCanAnswer.id", not(hasItem(scene.ana().id().toString())));
  }
}
