package io.github.rodrigofabreu.signalhub.event;

import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.github.rodrigofabreu.signalhub.TestProducers.asProducer;
import static io.github.rodrigofabreu.signalhub.event.Asking.EVENTS;
import static io.github.rodrigofabreu.signalhub.event.Asking.MERGE_OR_HOLD;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.contains;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.nullValue;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.github.rodrigofabreu.signalhub.TestClients;
import io.github.rodrigofabreu.signalhub.TestProducers;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.RestAssured;
import io.restassured.http.ContentType;
import io.restassured.response.ValidatableResponse;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.ArrayList;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/**
 * The producer's side of a question, against real PostgreSQL: reading the answer, holding the read
 * until something changes, and closing the question.
 */
@QuarkusTest
class EventQuestionProducerApiTest {

  private record Scene(
      TestProducers.Registered producer, TestClients.Registered owner, UUID event) {
    String answerUrl() {
      return EVENTS + "/" + event + "/answer";
    }
  }

  private static Scene scene(String ask) {
    var producer = TestProducers.registerPublic("question");
    var owner = TestClients.register("question-owner");
    return new Scene(producer, owner, Asking.publish(producer, ask));
  }

  private static void answer(Scene scene, String body) {
    asClient(scene.owner().clientKey())
        .contentType(ContentType.JSON)
        .body(body)
        .put(scene.answerUrl())
        .then()
        .statusCode(200);
  }

  private static ValidatableResponse read(Scene scene, String query) {
    return asProducer(scene.producer().apiKey()).get(scene.answerUrl() + query).then();
  }

  @Test
  void theProducerReadsAnOpenQuestionWithoutWaiting() {
    var scene = scene(MERGE_OR_HOLD);

    read(scene, "")
        .statusCode(200)
        .body("state", equalTo("OPEN"))
        .body("answer", nullValue())
        .body("closedBy", nullValue())
        .body("closedAt", nullValue())
        .body("closeNote", nullValue());
    read(scene, "?wait=0").statusCode(200).body("state", equalTo("OPEN"));
  }

  @Test
  void theProducerReadsTheAnswerWithWhoGaveItAndWhere() {
    var scene = scene(MERGE_OR_HOLD);
    answer(scene, "{\"choices\": [\"merge\"]}");

    read(scene, "")
        .statusCode(200)
        .body("state", equalTo("ANSWERED"))
        .body("answer.choices", contains("merge"))
        .body("answer.text", nullValue())
        .body("answer.by.id", equalTo(scene.owner().userId().toString()))
        .body("answer.via", equalTo("APP"))
        .body("answer.at", org.hamcrest.Matchers.notNullValue())
        .body("closedBy", nullValue());
  }

  @Test
  void anyKeyOfTheProducerReadsButNoOtherProducerDoes() {
    var scene = scene(MERGE_OR_HOLD);
    var second =
        asAdmin()
            .post(TestProducers.ADMIN + "/" + scene.producer().id() + "/keys")
            .then()
            .statusCode(201)
            .extract()
            .<String>path("apiKey");
    var other = TestProducers.register("question-other");

    asProducer(second).get(scene.answerUrl()).then().statusCode(200);
    asProducer(other.apiKey()).get(scene.answerUrl()).then().statusCode(404);
    asProducer(other.apiKey()).post(scene.answerUrl() + "/close").then().statusCode(404);
    given().get(scene.answerUrl()).then().statusCode(401);
    given().post(scene.answerUrl() + "/close").then().statusCode(401);
    asClient(scene.owner().clientKey()).get(scene.answerUrl()).then().statusCode(401);
    asAdmin().get(scene.answerUrl()).then().statusCode(401);
    asProducer(scene.producer().apiKey())
        .get(EVENTS + "/" + UUID.randomUUID() + "/answer")
        .then()
        .statusCode(404);
  }

  @Test
  void anEventThatAsksNothingIsAConflictToReadOrClose() {
    var producer = TestProducers.register("question-plain");
    var plain =
        asProducer(producer.apiKey())
            .contentType(ContentType.JSON)
            .body("{\"category\": \"INFO\", \"severity\": \"LOW\", \"title\": \"Plain\"}")
            .post(EVENTS)
            .then()
            .extract()
            .<String>path("id");

    asProducer(producer.apiKey()).get(EVENTS + "/" + plain + "/answer").then().statusCode(409);
    asProducer(producer.apiKey())
        .post(EVENTS + "/" + plain + "/answer/close")
        .then()
        .statusCode(409)
        .body("question", nullValue());
  }

  @ParameterizedTest
  @ValueSource(strings = {"61", "-1", "abc", "1.5", "0x10"})
  void waitIsAWholeNumberOfSecondsFromZeroToSixty(String wait) {
    var scene = scene(MERGE_OR_HOLD);

    read(scene, "?wait=" + wait).statusCode(400).body("violations.field", contains("wait"));
  }

  @Test
  void aHeldReadReturnsAtOnceWhenTheQuestionIsAnswered() throws Exception {
    var scene = scene(MERGE_OR_HOLD);
    var held = heldRead(scene, 30);
    pause(700);

    answer(scene, "{\"choices\": [\"hold\"]}");

    var response = held.get(10, TimeUnit.SECONDS);
    assertEquals(200, response.statusCode());
    assertTrue(response.body().contains("\"ANSWERED\""), response.body());
    assertTrue(response.body().contains("\"hold\""), response.body());
  }

  @Test
  void aHeldReadReturnsAtOnceWhenTheProducerClosesTheQuestion() throws Exception {
    var scene = scene(MERGE_OR_HOLD);
    var held = heldRead(scene, 30);
    pause(500);

    asProducer(scene.producer().apiKey()).post(scene.answerUrl() + "/close").then().statusCode(200);

    var response = held.get(10, TimeUnit.SECONDS);
    assertEquals(200, response.statusCode());
    assertTrue(response.body().contains("\"CLOSED\""), response.body());
    assertTrue(response.body().contains("\"PRODUCER\""), response.body());
  }

  @Test
  void aHeldReadReturnsWhenTheEventIsDeletedWhateverDeletedIt() throws Exception {
    var scene = scene(MERGE_OR_HOLD);
    var other = scene(MERGE_OR_HOLD);
    var held = heldRead(scene, 30);
    var bystander = heldRead(other, 3);
    pause(500);

    asAdmin().delete("/api/v1/admin/events/" + scene.event()).then().statusCode(204);

    assertEquals(404, held.get(10, TimeUnit.SECONDS).statusCode());
    // A read of another event re-reads too, and finds its question still open.
    assertEquals(200, bystander.get(10, TimeUnit.SECONDS).statusCode());
    assertTrue(bystander.get().body().contains("\"OPEN\""));
  }

  @Test
  void aHeldReadReturnsWhenTheQuestionsTimeIsUp() throws Exception {
    var scene =
        scene(
            "{\"choices\": [{\"id\": \"a\", \"label\": \"A\"}], \"closesAt\": \""
                + Asking.in(2)
                + "\"}");
    var started = System.nanoTime();

    var response = heldRead(scene, 30).get(15, TimeUnit.SECONDS);

    var seconds = Duration.ofNanos(System.nanoTime() - started).toMillis() / 1000.0;
    assertEquals(200, response.statusCode());
    assertTrue(response.body().contains("\"CLOSED\""), response.body());
    assertTrue(response.body().contains("\"TIME\""), response.body());
    assertTrue(seconds < 8, "returned at closesAt, not at the end of the wait: " + seconds);
  }

  @Test
  void aReadThatIsNotAnsweredReturnsTheOpenStateWhenItsWaitEnds() {
    var scene = scene(MERGE_OR_HOLD);
    var started = System.nanoTime();

    read(scene, "?wait=2").statusCode(200).body("state", equalTo("OPEN"));

    var millis = Duration.ofNanos(System.nanoTime() - started).toMillis();
    assertTrue(millis >= 1800 && millis < 8000, "waited " + millis + " ms");
  }

  @Test
  void aReadOfAnAnsweredQuestionDoesNotWait() {
    var scene = scene(MERGE_OR_HOLD);
    answer(scene, "{\"choices\": [\"merge\"]}");
    var started = System.nanoTime();

    read(scene, "?wait=30").statusCode(200).body("state", equalTo("ANSWERED"));

    assertTrue(Duration.ofNanos(System.nanoTime() - started).toSeconds() < 5);
  }

  @Test
  void atMostTwoHundredReadsWaitAndTheRestAnswerAtOnce() throws Exception {
    var scene = scene(MERGE_OR_HOLD);
    var held = new ArrayList<CompletableFuture<HttpResponse<String>>>();
    for (var i = 0; i < QuestionWakeups.MAX_WAITS; i++) {
      held.add(heldRead(scene, 20));
    }
    pause(2000);
    var started = System.nanoTime();

    var overflow = heldRead(scene, 20).get(10, TimeUnit.SECONDS);

    assertEquals(200, overflow.statusCode());
    assertTrue(overflow.body().contains("\"OPEN\""), overflow.body());
    assertTrue(Duration.ofNanos(System.nanoTime() - started).toSeconds() < 8);
    // The held ones are still held; one answer frees them all, and the places with them.
    assertTrue(held.stream().noneMatch(CompletableFuture::isDone));
    answer(scene, "{\"choices\": [\"merge\"]}");
    for (var future : held) {
      assertTrue(future.get(30, TimeUnit.SECONDS).body().contains("\"ANSWERED\""));
    }
    var again = heldRead(scene, 1).get(10, TimeUnit.SECONDS);
    assertTrue(again.body().contains("\"ANSWERED\""));
  }

  @Test
  void theProducerClosesAQuestionWithOrWithoutANote() {
    var withNote = scene(MERGE_OR_HOLD);
    var without = scene(MERGE_OR_HOLD);
    var empty = scene(MERGE_OR_HOLD);

    asProducer(withNote.producer().apiKey())
        .contentType(ContentType.JSON)
        .body("{\"note\": \"Answered in the session\"}")
        .post(withNote.answerUrl() + "/close")
        .then()
        .statusCode(200)
        .body("state", equalTo("CLOSED"))
        .body("closedBy", equalTo("PRODUCER"))
        .body("closedAt", org.hamcrest.Matchers.notNullValue())
        .body("closeNote", equalTo("Answered in the session"))
        .body("answer", nullValue());
    // No body and no content type at all.
    asProducer(without.producer().apiKey())
        .post(without.answerUrl() + "/close")
        .then()
        .statusCode(200)
        .body("closedBy", equalTo("PRODUCER"))
        .body("closeNote", nullValue());
    asProducer(empty.producer().apiKey())
        .contentType(ContentType.JSON)
        .body("{}")
        .post(empty.answerUrl() + "/close")
        .then()
        .statusCode(200)
        .body("closeNote", nullValue());
    read(withNote, "")
        .body("state", equalTo("CLOSED"))
        .body("closeNote", equalTo("Answered in the session"));
  }

  @Test
  void closingAgainKeepsTheFirstNoteAndTime() {
    var scene = scene(MERGE_OR_HOLD);
    var first =
        asProducer(scene.producer().apiKey())
            .contentType(ContentType.JSON)
            .body("{\"note\": \"first\"}")
            .post(scene.answerUrl() + "/close")
            .then()
            .statusCode(200)
            .extract();

    asProducer(scene.producer().apiKey())
        .contentType(ContentType.JSON)
        .body("{\"note\": \"second\"}")
        .post(scene.answerUrl() + "/close")
        .then()
        .statusCode(200)
        .body("closeNote", equalTo("first"))
        .body("closedAt", equalTo(first.path("closedAt")));
  }

  @ParameterizedTest
  @ValueSource(strings = {"\"\"", "\"   \"", "\"bad\\u0000\"", "5"})
  void aBadNoteIsRefused(String note) {
    var scene = scene(MERGE_OR_HOLD);

    asProducer(scene.producer().apiKey())
        .contentType(ContentType.JSON)
        .body("{\"note\": " + note + "}")
        .post(scene.answerUrl() + "/close")
        .then()
        .statusCode(400)
        .body("violations.field", hasItem("note"));
    read(scene, "").body("state", equalTo("OPEN"));
  }

  @Test
  void aNoteIsAtMostTwoHundredCharacters() {
    var scene = scene(MERGE_OR_HOLD);

    asProducer(scene.producer().apiKey())
        .contentType(ContentType.JSON)
        .body("{\"note\": \"" + "n".repeat(201) + "\"}")
        .post(scene.answerUrl() + "/close")
        .then()
        .statusCode(400);
    asProducer(scene.producer().apiKey())
        .contentType(ContentType.JSON)
        .body("{\"note\": \"" + "n".repeat(200) + "\", \"extra\": 1}")
        .post(scene.answerUrl() + "/close")
        .then()
        .statusCode(400);
    asProducer(scene.producer().apiKey())
        .contentType(ContentType.JSON)
        .body("{\"note\": \"" + "n".repeat(200) + "\"}")
        .post(scene.answerUrl() + "/close")
        .then()
        .statusCode(200);
  }

  @Test
  void closingAnAnsweredQuestionIsAConflictThatCarriesTheAnswer() {
    var scene = scene(MERGE_OR_HOLD);
    answer(scene, "{\"choices\": [\"merge\"]}");

    asProducer(scene.producer().apiKey())
        .post(scene.answerUrl() + "/close")
        .then()
        .statusCode(409)
        .body("question.state", equalTo("ANSWERED"))
        .body("question.answer.choices", contains("merge"))
        .body("question.answer.by.id", equalTo(scene.owner().userId().toString()));
    read(scene, "").body("state", equalTo("ANSWERED"));
  }

  @Test
  void closingAfterClosesAtSucceedsAndSaysTheTimeClosedIt() throws InterruptedException {
    var scene =
        scene(
            "{\"choices\": [{\"id\": \"a\", \"label\": \"A\"}], \"closesAt\": \""
                + Asking.in(2)
                + "\"}");
    Thread.sleep(2300);

    asProducer(scene.producer().apiKey())
        .contentType(ContentType.JSON)
        .body("{\"note\": \"too late\"}")
        .post(scene.answerUrl() + "/close")
        .then()
        .statusCode(200)
        .body("state", equalTo("CLOSED"))
        .body("closedBy", equalTo("TIME"))
        .body("closeNote", nullValue());
    read(scene, "").body("closedBy", equalTo("TIME"));
  }

  @Test
  void aDeletedEventCannotBeReadOrClosed() {
    var scene = scene(MERGE_OR_HOLD);
    asAdmin().delete("/api/v1/admin/events/" + scene.event()).then().statusCode(204);

    read(scene, "").statusCode(404);
    asProducer(scene.producer().apiKey()).post(scene.answerUrl() + "/close").then().statusCode(404);
  }

  @Test
  void aTestEventFromTheOperatorIsReadAndClosedLikeTheProducersOwn() {
    var producer = TestProducers.register("question-operator");
    var id =
        asAdmin()
            .contentType(ContentType.JSON)
            .body(Asking.event(MERGE_OR_HOLD))
            .post(TestProducers.ADMIN + "/" + producer.id() + "/events")
            .then()
            .statusCode(201)
            .extract()
            .<String>path("id");

    asProducer(producer.apiKey())
        .get(EVENTS + "/" + id + "/answer")
        .then()
        .statusCode(200)
        .body("state", equalTo("OPEN"));
    asProducer(producer.apiKey()).post(EVENTS + "/" + id + "/answer/close").then().statusCode(200);
    asAdmin().get(EVENTS + "/" + id).then().body("answerState", equalTo("CLOSED"));
  }

  // ---- A held read, made over HTTP so many can wait at once without a thread each.

  private static final HttpClient HTTP =
      HttpClient.newBuilder()
          // One connection per held read; HTTP/2 would multiplex them over one.
          .version(HttpClient.Version.HTTP_1_1)
          .executor(Executors.newVirtualThreadPerTaskExecutor())
          .build();

  private static CompletableFuture<HttpResponse<String>> heldRead(Scene scene, int wait) {
    var base = RestAssured.baseURI + ":" + RestAssured.port;
    return HTTP.sendAsync(
        HttpRequest.newBuilder(URI.create(base + scene.answerUrl() + "?wait=" + wait))
            .header("Authorization", "Bearer " + scene.producer().apiKey())
            .timeout(Duration.ofSeconds(90))
            .build(),
        HttpResponse.BodyHandlers.ofString());
  }

  private static void pause(long millis) {
    try {
      Thread.sleep(millis);
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      throw new IllegalStateException(e);
    }
  }
}
