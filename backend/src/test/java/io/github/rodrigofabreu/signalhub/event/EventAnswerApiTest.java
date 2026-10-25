package io.github.rodrigofabreu.signalhub.event;

import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.github.rodrigofabreu.signalhub.TestProducers.asProducer;
import static io.github.rodrigofabreu.signalhub.event.Asking.EVENTS;
import static io.github.rodrigofabreu.signalhub.event.Asking.MERGE_OR_HOLD;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.contains;
import static org.hamcrest.Matchers.empty;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.not;
import static org.hamcrest.Matchers.notNullValue;
import static org.hamcrest.Matchers.nullValue;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.github.rodrigofabreu.signalhub.TestBrowsers;
import io.github.rodrigofabreu.signalhub.TestClients;
import io.github.rodrigofabreu.signalhub.TestProducers;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import io.restassured.response.ValidatableResponse;
import io.restassured.specification.RequestSpecification;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.Executors;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

/**
 * Answering an event's question ({@code PUT /api/v1/events/{id}/answer}), against real PostgreSQL:
 * who may answer, what an answer may hold for each kind of question, the first answer winning, and
 * how the answer shows in the event, the listing and the counts.
 */
@QuarkusTest
class EventAnswerApiTest {

  private static final String CLIENT_PRODUCERS = "/api/v1/client/producers";

  /** A public producer, the owner's device (which owns it), and one asking event. */
  private record Scene(
      TestProducers.Registered producer, TestClients.Registered owner, UUID event) {

    String answerUrl() {
      return EVENTS + "/" + event + "/answer";
    }
  }

  private static Scene scene(String ask) {
    var producer = TestProducers.registerPublic("answer");
    var owner = TestClients.register("answer-owner");
    return new Scene(producer, owner, Asking.publish(producer, ask));
  }

  private static TestClients.Registered answerer(Scene scene) {
    var device = TestClients.registerSubscribed("BASIC", "answerer", scene.producer());
    asClient(scene.owner().clientKey())
        .put(CLIENT_PRODUCERS + "/" + scene.producer().id() + "/answerers/" + device.userId())
        .then()
        .statusCode(200);
    return device;
  }

  private static ValidatableResponse answer(
      TestClients.Registered device, Scene scene, String body) {
    return asClient(device.clientKey())
        .contentType(ContentType.JSON)
        .body(body)
        .put(scene.answerUrl())
        .then();
  }

  @Test
  void theOwnerAnswersAndTheEventShowsTheAnswerToEveryone() {
    var scene = scene(MERGE_OR_HOLD);

    answer(scene.owner(), scene, "{\"choices\": [\"merge\"]}")
        .statusCode(200)
        .body("choices", contains("merge"))
        .body("text", nullValue())
        .body("by.id", equalTo(scene.owner().userId().toString()))
        .body("by.name", notNullValue())
        .body("via", equalTo("APP"))
        .body("at", notNullValue());

    var seen =
        asClient(scene.owner().clientKey())
            .get(EVENTS + "/" + scene.event())
            .then()
            .statusCode(200)
            .body("answerState", equalTo("ANSWERED"))
            .body("answer.choices", contains("merge"))
            .body("answer.via", equalTo("APP"))
            .body("canAnswer", equalTo(false))
            .body("closedBy", nullValue());
    asAdmin()
        .get(EVENTS + "/" + scene.event())
        .then()
        .body("answerState", equalTo("ANSWERED"))
        .body("answer.by.name", equalTo(seen.extract().path("answer.by.name")))
        .body("canAnswer", equalTo(false));
  }

  @Test
  void anAnswererAnswersButOnlyTheFirstAnswerCounts() {
    var scene = scene(MERGE_OR_HOLD);
    var ana = answerer(scene);

    answer(ana, scene, "{\"choices\": [\"hold\"]}")
        .statusCode(200)
        .body("choices", contains("hold"));

    // The owner is second: refused, with Ana's answer in the body.
    answer(scene.owner(), scene, "{\"choices\": [\"merge\"]}")
        .statusCode(409)
        .body("status", equalTo(409))
        .body("question.state", equalTo("ANSWERED"))
        .body("question.answer.choices", contains("hold"))
        .body("question.answer.by.id", equalTo(ana.userId().toString()))
        .body("question.closedBy", nullValue());
    // Even the same choice is refused to someone else.
    answer(scene.owner(), scene, "{\"choices\": [\"hold\"]}")
        .statusCode(409)
        .body("question.state", equalTo("ANSWERED"));
  }

  @Test
  void theSamePersonSendingTheSameAnswerAgainGetsTheSameAnswerAndAnotherAnswerIsRefused() {
    var scene = scene(MERGE_OR_HOLD);

    var first =
        answer(scene.owner(), scene, "{\"choices\": [\"merge\"]}").statusCode(200).extract();
    answer(scene.owner(), scene, "{\"choices\": [\"merge\"], \"text\": null}")
        .statusCode(200)
        .body("at", equalTo(first.path("at")));
    answer(scene.owner(), scene, "{\"choices\": [\"hold\"]}")
        .statusCode(409)
        .body("question.answer.choices", contains("merge"));
  }

  @Test
  void aBrowserAnswersAsItsUserAndTheAnswerSaysItCameFromTheWeb() {
    var scene = scene(MERGE_OR_HOLD);
    var browser = TestBrowsers.signIn(scene.owner());

    browser
        .change()
        .body("{\"choices\": [\"hold\"]}")
        .put(scene.answerUrl())
        .then()
        .statusCode(200)
        .body("via", equalTo("WEB"))
        .body("by.id", equalTo(scene.owner().userId().toString()));
    asAdmin().get(EVENTS + "/" + scene.event()).then().body("answer.via", equalTo("WEB"));
  }

  @Test
  void aBrowserNeedsItsCsrfTokenToAnswer() {
    var scene = scene(MERGE_OR_HOLD);
    var browser = TestBrowsers.signIn(scene.owner());

    browser
        .get()
        .contentType(ContentType.JSON)
        .body("{\"choices\": [\"hold\"]}")
        .put(scene.answerUrl())
        .then()
        .statusCode(403);
    asAdmin().get(EVENTS + "/" + scene.event()).then().body("answerState", equalTo("OPEN"));
  }

  @Test
  void theAdminTokenAnswersNothingAndAProducerKeyIsNotACredential() {
    var scene = scene(MERGE_OR_HOLD);

    asAdmin()
        .contentType(ContentType.JSON)
        .body("{\"choices\": [\"merge\"]}")
        .put(scene.answerUrl())
        .then()
        .statusCode(403);
    asProducer(scene.producer().apiKey())
        .contentType(ContentType.JSON)
        .body("{\"choices\": [\"merge\"]}")
        .put(scene.answerUrl())
        .then()
        .statusCode(401);
    given()
        .contentType(ContentType.JSON)
        .body("{\"choices\": [\"merge\"]}")
        .put(scene.answerUrl())
        .then()
        .statusCode(401);
    asAdmin().get(EVENTS + "/" + scene.event()).then().body("answerState", equalTo("OPEN"));
  }

  @Test
  void aUserWhoDoesNotReceiveTheEventSeesNoSuchEventAndOneWhoMayNotAnswerIsForbidden() {
    var scene = scene(MERGE_OR_HOLD);
    var unsubscribed = TestClients.registerAs("BASIC", "answer-stranger");
    var reader = TestClients.registerSubscribed("BASIC", "answer-reader", scene.producer());

    answer(unsubscribed, scene, "{\"choices\": [\"merge\"]}").statusCode(404);
    answer(reader, scene, "{\"choices\": [\"merge\"]}").statusCode(403);
    // A malformed body is checked after who may answer, so the reader learns nothing from it.
    answer(reader, scene, "{\"choices\": [\"nope\"]}").statusCode(403);
    answer(scene.owner(), new Scene(scene.producer(), scene.owner(), UUID.randomUUID()), "{}")
        .statusCode(404);
    asAdmin().get(EVENTS + "/" + scene.event()).then().body("answerState", equalTo("OPEN"));
  }

  @Test
  void anEventThatAsksNothingIsAConflictWithAPlainError() {
    var producer = TestProducers.registerPublic("answer-plain");
    var owner = TestClients.register("answer-plain-owner");
    var plain =
        asProducer(producer.apiKey())
            .contentType(ContentType.JSON)
            .body("{\"category\": \"INFO\", \"severity\": \"LOW\", \"title\": \"Plain\"}")
            .post(EVENTS)
            .then()
            .extract()
            .<String>path("id");

    asClient(owner.clientKey())
        .contentType(ContentType.JSON)
        .body("{\"choices\": [\"merge\"]}")
        .put(EVENTS + "/" + plain + "/answer")
        .then()
        .statusCode(409)
        .body("question", nullValue())
        .body("title", equalTo("The event asks nothing"));
  }

  /** The ask, then the answers that are valid (V) or refused (X), in the order of the table. */
  @ParameterizedTest(name = "{0} {1} {2}")
  @CsvSource(
      delimiter = '|',
      value = {
        // A typed question: text only.
        "{}|V|{\"text\": \"after lunch\"}",
        "{}|X|{}",
        "{}|X|{\"text\": \"  \"}",
        "{}|X|{\"choices\": [\"a\"], \"text\": \"x\"}",
        // Single choice, no text.
        "{\"choices\": [{\"id\": \"a\", \"label\": \"A\"}, {\"id\": \"b\", \"label\": \"B\"}]}|V|{\"choices\": [\"b\"]}",
        "{\"choices\": [{\"id\": \"a\", \"label\": \"A\"}, {\"id\": \"b\", \"label\": \"B\"}]}|X|{\"choices\": []}",
        "{\"choices\": [{\"id\": \"a\", \"label\": \"A\"}, {\"id\": \"b\", \"label\": \"B\"}]}|X|{\"choices\": [\"a\", \"b\"]}",
        "{\"choices\": [{\"id\": \"a\", \"label\": \"A\"}, {\"id\": \"b\", \"label\": \"B\"}]}|X|{\"choices\": [\"c\"]}",
        "{\"choices\": [{\"id\": \"a\", \"label\": \"A\"}, {\"id\": \"b\", \"label\": \"B\"}]}|X|{\"choices\": [\"a\"], \"text\": \"why\"}",
        "{\"choices\": [{\"id\": \"a\", \"label\": \"A\"}, {\"id\": \"b\", \"label\": \"B\"}]}|X|{\"text\": \"why\"}",
        // Multiple, no text.
        "{\"choices\": [{\"id\": \"a\", \"label\": \"A\"}, {\"id\": \"b\", \"label\": \"B\"}], \"multiple\": true}|V|{\"choices\": [\"b\", \"a\"]}",
        "{\"choices\": [{\"id\": \"a\", \"label\": \"A\"}, {\"id\": \"b\", \"label\": \"B\"}], \"multiple\": true}|X|{\"choices\": [\"a\", \"a\"]}",
        "{\"choices\": [{\"id\": \"a\", \"label\": \"A\"}, {\"id\": \"b\", \"label\": \"B\"}], \"multiple\": true}|X|{}",
        // A note: optional or required, with exactly one choice.
        "{\"choices\": [{\"id\": \"a\", \"label\": \"A\"}], \"text\": \"OPTIONAL\"}|V|{\"choices\": [\"a\"]}",
        "{\"choices\": [{\"id\": \"a\", \"label\": \"A\"}], \"text\": \"OPTIONAL\"}|V|{\"choices\": [\"a\"], \"text\": \"note\"}",
        "{\"choices\": [{\"id\": \"a\", \"label\": \"A\"}], \"text\": \"OPTIONAL\"}|X|{\"text\": \"note\"}",
        "{\"choices\": [{\"id\": \"a\", \"label\": \"A\"}], \"text\": \"REQUIRED\"}|V|{\"choices\": [\"a\"], \"text\": \"note\"}",
        "{\"choices\": [{\"id\": \"a\", \"label\": \"A\"}], \"text\": \"REQUIRED\"}|X|{\"choices\": [\"a\"]}",
        // An Other row, single: a choice or the text, not both and not neither.
        "{\"choices\": [{\"id\": \"a\", \"label\": \"A\"}], \"text\": \"OPTIONAL\", \"textStyle\": \"OTHER\"}|V|{\"choices\": [\"a\"]}",
        "{\"choices\": [{\"id\": \"a\", \"label\": \"A\"}], \"text\": \"OPTIONAL\", \"textStyle\": \"OTHER\"}|V|{\"text\": \"Something else\"}",
        "{\"choices\": [{\"id\": \"a\", \"label\": \"A\"}], \"text\": \"OPTIONAL\", \"textStyle\": \"OTHER\"}|X|{\"choices\": [\"a\"], \"text\": \"both\"}",
        "{\"choices\": [{\"id\": \"a\", \"label\": \"A\"}], \"text\": \"OPTIONAL\", \"textStyle\": \"OTHER\"}|X|{}",
        // An Other row, multiple: ticked with the choices, or alone.
        "{\"choices\": [{\"id\": \"a\", \"label\": \"A\"}, {\"id\": \"b\", \"label\": \"B\"}], \"multiple\": true, \"text\": \"OPTIONAL\", \"textStyle\": \"OTHER\"}|V|{\"choices\": [\"a\"], \"text\": \"and more\"}",
        "{\"choices\": [{\"id\": \"a\", \"label\": \"A\"}, {\"id\": \"b\", \"label\": \"B\"}], \"multiple\": true, \"text\": \"OPTIONAL\", \"textStyle\": \"OTHER\"}|V|{\"text\": \"only other\"}",
        "{\"choices\": [{\"id\": \"a\", \"label\": \"A\"}, {\"id\": \"b\", \"label\": \"B\"}], \"multiple\": true, \"text\": \"OPTIONAL\", \"textStyle\": \"OTHER\"}|X|{}",
      })
  void checksTheAnswerAgainstTheQuestion(String ask, String verdict, String body) {
    var scene = scene(ask);

    var response = answer(scene.owner(), scene, body);
    if (verdict.equals("V")) {
      response.statusCode(200);
    } else {
      response.statusCode(400);
      asAdmin().get(EVENTS + "/" + scene.event()).then().body("answerState", equalTo("OPEN"));
    }
  }

  @Test
  void textIsBoundedAndKeptAsTyped() {
    var scene = scene("{}");

    answer(scene.owner(), scene, "{\"text\": \"" + "x".repeat(3001) + "\"}")
        .statusCode(400)
        .body("violations.field", hasItem("text"));
    answer(scene.owner(), scene, "{\"text\": \"bad\\u0000\"}")
        .statusCode(400)
        .body("violations.field", hasItem("text"));
    answer(scene.owner(), scene, "{\"text\": \"" + "x".repeat(3000) + "\"}")
        .statusCode(200)
        .body("text", equalTo("x".repeat(3000)));
  }

  @Test
  void aWrongAnswerNamesTheFieldAndStoresChoicesInTheQuestionsOrder() {
    var scene =
        scene(
            "{\"choices\": [{\"id\": \"a\", \"label\": \"A\"}, {\"id\": \"b\", \"label\": \"B\"},"
                + " {\"id\": \"c\", \"label\": \"C\"}], \"multiple\": true}");

    answer(scene.owner(), scene, "{\"choices\": [\"zzz\"]}")
        .statusCode(400)
        .body("violations.field", contains("choices"));
    answer(scene.owner(), scene, "{\"choices\": [\"c\", \"a\"]}")
        .statusCode(200)
        .body("choices", contains("a", "c"));
  }

  @Test
  void aQuestionClosedByTimeIsRefusedWithTheStateAndShowsClosed() throws InterruptedException {
    var scene =
        scene(
            "{\"choices\": [{\"id\": \"a\", \"label\": \"A\"}], \"closesAt\": \""
                + Asking.in(2)
                + "\"}");

    asClient(scene.owner().clientKey())
        .get(EVENTS + "/" + scene.event())
        .then()
        .body("answerState", equalTo("OPEN"))
        .body("canAnswer", equalTo(true));
    Thread.sleep(2300);

    asClient(scene.owner().clientKey())
        .get(EVENTS + "/" + scene.event())
        .then()
        .body("answerState", equalTo("CLOSED"))
        .body("closedBy", equalTo("TIME"))
        .body("closedAt", notNullValue())
        .body("closeNote", nullValue())
        .body("canAnswer", equalTo(false))
        .body(
            "ask.closesAt",
            equalTo(asAdmin().get(EVENTS + "/" + scene.event()).then().extract().path("closedAt")));
    answer(scene.owner(), scene, "{\"choices\": [\"a\"]}")
        .statusCode(409)
        .body("question.state", equalTo("CLOSED"))
        .body("question.closedBy", equalTo("TIME"))
        .body("question.answer", nullValue());
  }

  @Test
  void aQuestionTheProducerClosedIsRefusedWithWhoClosedIt() {
    var scene = scene(MERGE_OR_HOLD);

    asProducer(scene.producer().apiKey())
        .contentType(ContentType.JSON)
        .body("{\"note\": \"Answered in the session\"}")
        .post(scene.answerUrl() + "/close")
        .then()
        .statusCode(200);

    answer(scene.owner(), scene, "{\"choices\": [\"merge\"]}")
        .statusCode(409)
        .body("question.state", equalTo("CLOSED"))
        .body("question.closedBy", equalTo("PRODUCER"))
        .body("question.closeNote", equalTo("Answered in the session"));
    asClient(scene.owner().clientKey())
        .get(EVENTS + "/" + scene.event())
        .then()
        .body("answerState", equalTo("CLOSED"))
        .body("closedBy", equalTo("PRODUCER"))
        .body("closeNote", equalTo("Answered in the session"))
        .body("canAnswer", equalTo(false));
  }

  @Test
  void aDeletedEventTakesItsAnswerWithItAndIsNotFound() {
    var scene = scene(MERGE_OR_HOLD);
    answer(scene.owner(), scene, "{\"choices\": [\"merge\"]}").statusCode(200);

    asAdmin().delete("/api/v1/admin/events/" + scene.event()).then().statusCode(204);

    answer(scene.owner(), scene, "{\"choices\": [\"merge\"]}").statusCode(404);
    asAdmin().get(EVENTS + "/" + scene.event()).then().statusCode(404);
  }

  @Test
  void aDisabledProducersQuestionCanStillBeAnswered() {
    var scene = scene(MERGE_OR_HOLD);
    asAdmin()
        .post(TestProducers.ADMIN + "/" + scene.producer().id() + "/disable")
        .then()
        .statusCode(200);

    answer(scene.owner(), scene, "{\"choices\": [\"merge\"]}").statusCode(200);
    // The producer cannot read it while disabled; it can once enabled again.
    asProducer(scene.producer().apiKey()).get(scene.answerUrl()).then().statusCode(401);
    asAdmin()
        .post(TestProducers.ADMIN + "/" + scene.producer().id() + "/enable")
        .then()
        .statusCode(200);
    asProducer(scene.producer().apiKey())
        .get(scene.answerUrl())
        .then()
        .statusCode(200)
        .body("state", equalTo("ANSWERED"));
  }

  @Test
  void manyAnswerersAnsweringAtOnceLeaveExactlyOneWinner() throws Exception {
    var scene = scene(MERGE_OR_HOLD);
    var devices = new ArrayList<TestClients.Registered>();
    devices.add(scene.owner());
    for (var i = 0; i < 7; i++) {
      devices.add(answerer(scene));
    }
    var pool = Executors.newFixedThreadPool(devices.size());
    try {
      var attempts = new ArrayList<Callable<Integer>>();
      for (var i = 0; i < devices.size(); i++) {
        var device = devices.get(i);
        var choice = i % 2 == 0 ? "merge" : "hold";
        attempts.add(
            () ->
                asClient(device.clientKey())
                    .contentType(ContentType.JSON)
                    .body("{\"choices\": [\"" + choice + "\"]}")
                    .put(scene.answerUrl())
                    .statusCode());
      }
      var statuses = new ArrayList<Integer>();
      for (var done : pool.invokeAll(attempts)) {
        statuses.add(done.get());
      }

      assertEquals(1, statuses.stream().filter(s -> s == 200).count(), statuses.toString());
      assertEquals(devices.size() - 1, statuses.stream().filter(s -> s == 409).count());
    } finally {
      pool.shutdownNow();
    }
    // The stored answer is the winner's, whatever order the requests finished in.
    var stored = asAdmin().get(EVENTS + "/" + scene.event()).then().extract();
    assertEquals("ANSWERED", stored.path("answerState"));
    assertEquals(1, stored.<List<String>>path("answer.choices").size());
  }

  @Test
  void anAnswerAndTheProducersCloseRacingLeaveExactlyOneOutcome() throws Exception {
    for (var round = 0; round < 5; round++) {
      var scene = scene(MERGE_OR_HOLD);
      var pool = Executors.newFixedThreadPool(2);
      try {
        var answered =
            pool.submit(
                () ->
                    asClient(scene.owner().clientKey())
                        .contentType(ContentType.JSON)
                        .body("{\"choices\": [\"merge\"]}")
                        .put(scene.answerUrl())
                        .statusCode());
        var closed =
            pool.submit(
                () ->
                    asProducer(scene.producer().apiKey())
                        .contentType(ContentType.JSON)
                        .post(scene.answerUrl() + "/close")
                        .statusCode());
        var answerStatus = answered.get();
        var closeStatus = closed.get();

        var state =
            asAdmin()
                .get(EVENTS + "/" + scene.event())
                .then()
                .extract()
                .<String>path("answerState");
        if (state.equals("ANSWERED")) {
          assertEquals(List.of(200, 409), List.of(answerStatus, closeStatus));
        } else {
          assertEquals("CLOSED", state);
          assertEquals(List.of(409, 200), List.of(answerStatus, closeStatus));
        }
      } finally {
        pool.shutdownNow();
      }
    }
  }

  @Test
  void aToAnswerListingHoldsTheOpenQuestionsTheCallerMayAnswer() {
    var scene = scene(MERGE_OR_HOLD);
    var answered = Asking.publish(scene.producer(), MERGE_OR_HOLD);
    var plain =
        asProducer(scene.producer().apiKey())
            .contentType(ContentType.JSON)
            .body("{\"category\": \"INFO\", \"severity\": \"LOW\", \"title\": \"Plain\"}")
            .post(EVENTS)
            .then()
            .extract()
            .<String>path("id");
    asClient(scene.owner().clientKey())
        .contentType(ContentType.JSON)
        .body("{\"choices\": [\"hold\"]}")
        .put(EVENTS + "/" + answered + "/answer")
        .then()
        .statusCode(200);
    var reader = TestClients.registerSubscribed("BASIC", "to-answer-reader", scene.producer());

    asClient(scene.owner().clientKey())
        .queryParam("producerId", scene.producer().id().toString())
        .queryParam("toAnswer", "true")
        .get(EVENTS)
        .then()
        .statusCode(200)
        .body("items.id", contains(scene.event().toString()))
        .body("items[0].canAnswer", equalTo(true));
    // A reader who may not answer, and the operator who answers nothing, have none to answer.
    asClient(reader.clientKey())
        .queryParam("toAnswer", "true")
        .get(EVENTS)
        .then()
        .statusCode(200)
        .body("items", empty());
    asAdmin()
        .queryParam("producerId", scene.producer().id().toString())
        .queryParam("toAnswer", "true")
        .queryParam("total", "true")
        .get(EVENTS)
        .then()
        .statusCode(200)
        .body("items", empty())
        .body("total", equalTo(0));
    // Any value but true is a mistake.
    asClient(scene.owner().clientKey())
        .queryParam("toAnswer", "false")
        .get(EVENTS)
        .then()
        .statusCode(400)
        .body("violations.field", contains("toAnswer"));
    // An open question stays in the list once read, until it is answered.
    asClient(scene.owner().clientKey())
        .put(EVENTS + "/" + scene.event() + "/read")
        .then()
        .statusCode(200);
    asClient(scene.owner().clientKey())
        .queryParam("producerId", scene.producer().id().toString())
        .queryParam("toAnswer", "true")
        .get(EVENTS)
        .then()
        .body("items.id", contains(scene.event().toString()));
    assertTrue(plain != null);
  }

  @Test
  void theUnreadCountSaysHowManyQuestionsTheCallerMayAnswer() {
    var producer = TestProducers.registerPublic("answer-count");
    var owner = TestClients.registerSubscribed("BASIC", "count-reader", producer);
    var ownerOfProducer = TestClients.register("count-owner");
    var first = Asking.publish(producer, MERGE_OR_HOLD);
    Asking.publish(producer, "{}");

    // The owner of the producer may answer both, a plain reader neither.
    var before = counts(ownerOfProducer);
    var after =
        counts(
            ownerOfProducer,
            () ->
                asClient(ownerOfProducer.clientKey())
                    .contentType(ContentType.JSON)
                    .body("{\"choices\": [\"merge\"]}")
                    .put(EVENTS + "/" + first + "/answer")
                    .then()
                    .statusCode(200));
    assertEquals(before - 1, after);
    asClient(owner.clientKey()).get(EVENTS + "/unread-count").then().body("toAnswer", equalTo(0));
    asAdmin().get(EVENTS + "/unread-count").then().body("toAnswer", equalTo(0));
  }

  private static long counts(TestClients.Registered device, Runnable between) {
    between.run();
    return counts(device);
  }

  private static long counts(TestClients.Registered device) {
    return asClient(device.clientKey())
        .get(EVENTS + "/unread-count")
        .then()
        .statusCode(200)
        .extract()
        .<Number>path("toAnswer")
        .longValue();
  }

  @Test
  void theOperatorsListingFiltersByHowTheQuestionStands() throws InterruptedException {
    var producer = TestProducers.registerPublic("answer-filter");
    var owner = TestClients.register("answer-filter-owner");
    var plain =
        asProducer(producer.apiKey())
            .contentType(ContentType.JSON)
            .body("{\"category\": \"INFO\", \"severity\": \"LOW\", \"title\": \"Plain\"}")
            .post(EVENTS)
            .then()
            .extract()
            .<String>path("id");
    var open = Asking.publish(producer, MERGE_OR_HOLD);
    var answered = Asking.publish(producer, MERGE_OR_HOLD);
    var closedByProducer = Asking.publish(producer, MERGE_OR_HOLD);
    var closedByTime = Asking.publish(producer, "{\"closesAt\": \"" + Asking.in(1) + "\"}");
    asClient(owner.clientKey())
        .contentType(ContentType.JSON)
        .body("{\"choices\": [\"merge\"]}")
        .put(EVENTS + "/" + answered + "/answer")
        .then()
        .statusCode(200);
    asProducer(producer.apiKey())
        .post(EVENTS + "/" + closedByProducer + "/answer/close")
        .then()
        .statusCode(200);
    Thread.sleep(1300);

    assertEquals(List.of(open.toString()), filtered(producer, "OPEN"));
    assertEquals(List.of(answered.toString()), filtered(producer, "ANSWERED"));
    assertEquals(
        sorted(closedByProducer.toString(), closedByTime.toString()),
        sorted(filtered(producer, "CLOSED")));
    assertEquals(List.of(plain), filtered(producer, "NONE"));
    assertEquals(
        sorted(open.toString(), answered.toString()),
        sorted(filtered(producer, "OPEN", "ANSWERED")));
    // A client key may not ask: it is the operator's filter.
    asClient(owner.clientKey())
        .queryParam("answerState", "OPEN")
        .get(EVENTS)
        .then()
        .statusCode(400)
        .body("violations.field", contains("answerState"));
    asAdmin()
        .queryParam("answerState", "MAYBE")
        .get(EVENTS)
        .then()
        .statusCode(400)
        .body("violations.field", contains("answerState"));
  }

  private static List<String> filtered(TestProducers.Registered producer, String... states) {
    RequestSpecification request =
        asAdmin().queryParam("producerId", producer.id().toString()).queryParam("limit", "100");
    for (var state : states) {
      request = request.queryParam("answerState", state);
    }
    return request.get(EVENTS).then().statusCode(200).extract().path("items.id");
  }

  private static List<String> sorted(List<String> ids) {
    return ids.stream().sorted().toList();
  }

  private static List<String> sorted(String... ids) {
    return sorted(List.of(ids));
  }

  @Test
  void aBulkDeleteCountsHowManyOfTheEventsAskADryRunToo() {
    var producer = TestProducers.register("answer-delete");
    var asking = Asking.publish(producer, MERGE_OR_HOLD);
    var plain =
        asProducer(producer.apiKey())
            .contentType(ContentType.JSON)
            .body("{\"category\": \"INFO\", \"severity\": \"LOW\", \"title\": \"Plain\"}")
            .post(EVENTS)
            .then()
            .extract()
            .<String>path("id");
    var delete = "/api/v1/admin/events/delete";

    asAdmin()
        .contentType(ContentType.JSON)
        .body("{\"ids\": [\"%s\", \"%s\"], \"dryRun\": true}".formatted(asking, plain))
        .post(delete)
        .then()
        .statusCode(200)
        .body("count", equalTo(2))
        .body("asking", equalTo(1))
        .body("dryRun", equalTo(true));
    asAdmin()
        .contentType(ContentType.JSON)
        .body(
            "{\"producerId\": \"%s\", \"createdBefore\": \"2999-01-01T00:00:00Z\", \"dryRun\": true}"
                .formatted(producer.id()))
        .post(delete)
        .then()
        .statusCode(200)
        .body("count", equalTo(2))
        .body("asking", equalTo(1));
    asAdmin()
        .contentType(ContentType.JSON)
        .body("{\"producerId\": \"%s\"}".formatted(producer.id()))
        .post(delete)
        .then()
        .statusCode(200)
        .body("count", equalTo(2))
        .body("asking", equalTo(1))
        .body("dryRun", equalTo(false));
    asAdmin().get(EVENTS + "/" + asking).then().statusCode(404);
  }

  @Test
  void whoCanAnswerListsTheOwnerFirstThenTheAnswerersAndNotRevokedUsers() {
    var scene = scene(MERGE_OR_HOLD);
    var ana = answerer(scene);
    var bo = answerer(scene);
    var ownerName =
        asAdmin()
            .get(TestProducers.ADMIN + "/" + scene.producer().id())
            .then()
            .extract()
            .<String>path("owner.name");

    var names =
        asClient(scene.owner().clientKey())
            .get(EVENTS + "/" + scene.event())
            .then()
            .statusCode(200)
            .extract()
            .<List<String>>path("ask.whoCanAnswer.name");
    assertEquals(ownerName, names.get(0));
    assertEquals(3, names.size());

    asAdmin().post("/api/v1/admin/users/" + ana.userId() + "/revoke").then().statusCode(200);

    asClient(scene.owner().clientKey())
        .get(EVENTS + "/" + scene.event())
        .then()
        .body("ask.whoCanAnswer.id", not(hasItem(ana.userId().toString())))
        .body("ask.whoCanAnswer.id", hasItem(bo.userId().toString()))
        .body("ask.whoCanAnswer.id[0]", equalTo(scene.owner().userId().toString()));
  }
}
