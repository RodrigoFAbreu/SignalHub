package io.github.rodrigofabreu.signalhub.event;

import static io.github.rodrigofabreu.signalhub.TestClients.CLIENT;
import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.github.rodrigofabreu.signalhub.TestProducers.asProducer;
import static io.github.rodrigofabreu.signalhub.event.Asking.EVENTS;
import static io.github.rodrigofabreu.signalhub.event.Asking.MERGE_OR_HOLD;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.agroal.api.AgroalDataSource;
import io.github.rodrigofabreu.signalhub.TestClients;
import io.github.rodrigofabreu.signalhub.TestProducers;
import io.github.rodrigofabreu.signalhub.push.FakePushProvider;
import io.github.rodrigofabreu.signalhub.push.PushOutcome;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import jakarta.inject.Inject;
import java.sql.SQLException;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * What the pushes do about a question, on real PostgreSQL with the fake provider: the notification
 * tag, the data-only {@code answered}, {@code closed} and {@code deleted} notices (stored, sent
 * once, to the right devices), the close due at {@code closesAt}, and the event push that is
 * skipped once its question left OPEN. The scheduler is off in tests, so each test runs the
 * dispatchers itself.
 */
@QuarkusTest
class QuestionNoticesTest {

  @Inject EventPushDispatcher dispatcher;
  @Inject QuestionNoticeDispatcher noticeDispatcher;
  @Inject FakePushProvider fake;
  @Inject AgroalDataSource dataSource;

  /** A device with a push target, which owns the producer or reads it. */
  private record Device(TestClients.Registered client, String token) {}

  private TestProducers.Registered producer;
  private Device owner;
  // Other tests' devices are subscribed to public producers too; only these are asserted on.
  private final List<Device> mine = new java.util.ArrayList<>();

  @BeforeEach
  void setUp() {
    // Events and notices of other tests go first.
    dispatcher.dispatchPending();
    noticeDispatcher.sendDue();
    fake.answer((token, message) -> PushOutcome.delivered());
    producer = TestProducers.registerPublic("notices");
    mine.clear();
    owner = device(TestClients.register("notices-owner"));
  }

  private Device device(TestClients.Registered client) {
    var token = "notice-" + UUID.randomUUID();
    asClient(client.clientKey())
        .contentType(ContentType.JSON)
        .body(Map.of("provider", FakePushProvider.NAME, "token", token))
        .put(CLIENT + "/push-target")
        .then()
        .statusCode(200);
    var device = new Device(client, token);
    mine.add(device);
    return device;
  }

  private Device reader() {
    return device(TestClients.registerSubscribed("BASIC", "notices-reader", producer));
  }

  private UUID ask(String ask) {
    return Asking.publish(producer, ask);
  }

  private void answer(Device device, UUID event, String choice) {
    asClient(device.client().clientKey())
        .contentType(ContentType.JSON)
        .body("{\"choices\": [\"" + choice + "\"]}")
        .put(EVENTS + "/" + event + "/answer")
        .then()
        .statusCode(200);
  }

  /** Pushes sent for the event: the event's own pushes, then its notices, by notice name. */
  private List<FakePushProvider.Sent> sent(UUID event) {
    var tokens = mine.stream().map(Device::token).toList();
    return fake.sent().stream()
        .filter(s -> event.toString().equals(s.message().data().get("eventId")))
        .filter(s -> tokens.contains(s.token()))
        .toList();
  }

  /** One field of the delivery records of the event's pushes to this test's devices. */
  private List<String> records(UUID event, String field) {
    var ids =
        mine.stream()
            .map(d -> "'" + d.client().id() + "'")
            .collect(java.util.stream.Collectors.joining(","));
    return asAdmin()
        .get("/api/v1/admin/events/" + event + "/deliveries")
        .then()
        .statusCode(200)
        .extract()
        .path("items.findAll { it.clientId in [" + ids + "] }." + field);
  }

  private List<String> noticeTokens(UUID event, String notice) {
    return sent(event).stream()
        .filter(s -> notice.equals(s.message().data().get("notice")))
        .map(FakePushProvider.Sent::token)
        .sorted()
        .toList();
  }

  private static List<String> sorted(String... tokens) {
    return List.of(tokens).stream().sorted().toList();
  }

  @Test
  void everyEventPushCarriesTheEventIdAsItsNotificationTag() {
    var event = ask(MERGE_OR_HOLD);
    dispatcher.dispatchPending();

    var pushes = sent(event);
    assertFalse(pushes.isEmpty());
    for (var push : pushes) {
      assertEquals(event.toString(), push.message().tag());
      assertFalse(push.message().isDataOnly());
    }
  }

  @Test
  void anAnswerSendsAnAnsweredNoticeToTheDevicesShownTheEventExceptTheAnswering() {
    var reader = reader();
    var event = ask(MERGE_OR_HOLD);
    dispatcher.dispatchPending();
    fake.answer((token, message) -> PushOutcome.delivered());

    answer(owner, event, "merge");
    noticeDispatcher.sendDue();

    assertEquals(List.of(reader.token()), noticeTokens(event, "answered"));
    var notice = sent(event).get(0).message();
    assertTrue(notice.isDataOnly());
    assertEquals(Map.of("notice", "answered", "eventId", event.toString()), notice.data());
    // Sent once: the next run has nothing left.
    fake.answer((token, message) -> PushOutcome.delivered());
    noticeDispatcher.sendDue();
    assertTrue(sent(event).isEmpty());
  }

  @Test
  void theNoticeWaitsWhileTheEventsOwnPushIsStillToBeDispatched() {
    var reader = reader();
    var event = ask(MERGE_OR_HOLD);
    // Answered before the first dispatch: the notice must not go out ahead of the push.
    answer(owner, event, "merge");

    noticeDispatcher.sendDue();
    assertTrue(sent(event).isEmpty());

    dispatcher.dispatchPending();
    // The push itself is skipped now that the question is answered.
    assertTrue(sent(event).isEmpty());
    noticeDispatcher.sendDue();
    assertTrue(sent(event).isEmpty());
    assertTrue(reader.token() != null);
  }

  @Test
  void aPushDueAfterTheQuestionWasAnsweredIsSkippedAndRecordedAsFiltered() {
    var reader = reader();
    var event = ask(MERGE_OR_HOLD);
    answer(owner, event, "hold");

    dispatcher.dispatchPending();

    assertTrue(sent(event).isEmpty());
    var outcomes = records(event, "outcome");
    var details = records(event, "detail");
    assertFalse(outcomes.isEmpty());
    assertTrue(outcomes.stream().allMatch("FILTERED"::equals), outcomes.toString());
    assertTrue(details.stream().allMatch("question answered"::equals), details.toString());
    assertTrue(reader.token() != null);
  }

  @Test
  void aPushDueAfterTheProducerClosedTheQuestionSaysItWasClosed() {
    var event = ask(MERGE_OR_HOLD);
    asProducer(producer.apiKey())
        .post(EVENTS + "/" + event + "/answer/close")
        .then()
        .statusCode(200);

    dispatcher.dispatchPending();

    assertTrue(sent(event).isEmpty());
    assertFalse(records(event, "detail").isEmpty());
    assertTrue(records(event, "detail").stream().allMatch("question closed"::equals));
  }

  @Test
  void aPushRetryDueAfterTheQuestionLeftOpenIsSkipped() {
    var event = ask(MERGE_OR_HOLD);
    fake.answer((token, message) -> new PushOutcome(PushOutcome.Status.TRANSIENT_FAILURE, "busy"));
    dispatcher.dispatchPending();
    assertFalse(sent(event).isEmpty());

    answer(owner, event, "merge");
    asAdmin().get("/api/v1/admin/events/" + event + "/deliveries").then().statusCode(200);
    makeRetriesDue(event);
    fake.answer((token, message) -> PushOutcome.delivered());
    dispatcher.dispatchPending();

    assertTrue(sent(event).isEmpty(), "no retry is sent for an answered question");
    assertTrue(records(event, "detail").contains("question answered"));
  }

  @Test
  void theProducersCloseSendsAClosedNoticeAtOnce() {
    var reader = reader();
    var event = ask(MERGE_OR_HOLD);
    dispatcher.dispatchPending();
    fake.answer((token, message) -> PushOutcome.delivered());

    asProducer(producer.apiKey())
        .post(EVENTS + "/" + event + "/answer/close")
        .then()
        .statusCode(200);
    noticeDispatcher.sendDue();

    assertEquals(sorted(owner.token(), reader.token()), noticeTokens(event, "closed"));
  }

  @Test
  void repeatingTheCloseOrTheSameAnswerSendsNoSecondNotice() {
    var reader = reader();
    var event = ask(MERGE_OR_HOLD);
    dispatcher.dispatchPending();
    answer(owner, event, "merge");
    noticeDispatcher.sendDue();
    fake.answer((token, message) -> PushOutcome.delivered());

    answer(owner, event, "merge");
    asProducer(producer.apiKey())
        .post(EVENTS + "/" + event + "/answer/close")
        .then()
        .statusCode(409);
    noticeDispatcher.sendDue();

    assertTrue(sent(event).isEmpty());
    assertTrue(reader.token() != null);
  }

  @Test
  void aQuestionClosedByTimeSendsAClosedNoticeAtItsClosesAt() throws Exception {
    var reader = reader();
    var event =
        ask(
            "{\"choices\": [{\"id\": \"a\", \"label\": \"A\"}], \"closesAt\": \""
                + Asking.in(2)
                + "\"}");
    dispatcher.dispatchPending();
    fake.answer((token, message) -> PushOutcome.delivered());

    noticeDispatcher.sendDue();
    assertTrue(noticeTokens(event, "closed").isEmpty(), "not before it is due");
    Thread.sleep(2300);
    noticeDispatcher.sendDue();

    assertEquals(sorted(owner.token(), reader.token()), noticeTokens(event, "closed"));
  }

  @Test
  void aQuestionAnsweredBeforeItsClosesAtSendsOnlyTheAnsweredNotice() throws Exception {
    var reader = reader();
    var event =
        ask(
            "{\"choices\": [{\"id\": \"a\", \"label\": \"A\"}], \"closesAt\": \""
                + Asking.in(2)
                + "\"}");
    dispatcher.dispatchPending();
    fake.answer((token, message) -> PushOutcome.delivered());
    answer(owner, event, "a");

    Thread.sleep(2300);
    noticeDispatcher.sendDue();

    assertTrue(noticeTokens(event, "closed").isEmpty());
    assertEquals(List.of(reader.token()), noticeTokens(event, "answered"));
  }

  @Test
  void deletingAnOpenQuestionSendsADeletedNoticeToTheDevicesItWasShownTo() {
    var reader = reader();
    var event = ask(MERGE_OR_HOLD);
    dispatcher.dispatchPending();
    fake.answer((token, message) -> PushOutcome.delivered());

    asAdmin().delete("/api/v1/admin/events/" + event).then().statusCode(204);
    noticeDispatcher.sendDue();

    assertEquals(sorted(owner.token(), reader.token()), noticeTokens(event, "deleted"));
  }

  @Test
  void everyWayOfDeletingAnOpenQuestionSendsTheNotice() {
    var reader = reader();
    var selected = ask(MERGE_OR_HOLD);
    var byProducer = ask(MERGE_OR_HOLD);
    dispatcher.dispatchPending();
    fake.answer((token, message) -> PushOutcome.delivered());

    asAdmin()
        .contentType(ContentType.JSON)
        .body("{\"ids\": [\"" + selected + "\"]}")
        .post("/api/v1/admin/events/delete")
        .then()
        .statusCode(200);
    asAdmin()
        .contentType(ContentType.JSON)
        .body("{\"producerId\": \"" + producer.id() + "\"}")
        .post("/api/v1/admin/events/delete")
        .then()
        .statusCode(200);
    noticeDispatcher.sendDue();

    assertEquals(sorted(owner.token(), reader.token()), noticeTokens(selected, "deleted"));
    assertEquals(sorted(owner.token(), reader.token()), noticeTokens(byProducer, "deleted"));
  }

  @Test
  void deletingAnAnsweredOrClosedQuestionSendsNoNotice() {
    reader();
    var answered = ask(MERGE_OR_HOLD);
    var closed = ask(MERGE_OR_HOLD);
    var plain = ask("{}");
    dispatcher.dispatchPending();
    answer(owner, answered, "merge");
    asProducer(producer.apiKey())
        .post(EVENTS + "/" + closed + "/answer/close")
        .then()
        .statusCode(200);
    noticeDispatcher.sendDue();
    fake.answer((token, message) -> PushOutcome.delivered());

    for (var event : List.of(answered, closed)) {
      asAdmin().delete("/api/v1/admin/events/" + event).then().statusCode(204);
    }
    noticeDispatcher.sendDue();

    assertTrue(sent(answered).isEmpty());
    assertTrue(sent(closed).isEmpty());
    assertTrue(plain != null);
  }

  @Test
  void deletingAnEventThatAsksNothingSendsNoNotice() {
    reader();
    var plain =
        UUID.fromString(
            asProducer(producer.apiKey())
                .contentType(ContentType.JSON)
                .body("{\"category\": \"INFO\", \"severity\": \"LOW\", \"title\": \"Plain\"}")
                .post(EVENTS)
                .then()
                .extract()
                .path("id"));
    dispatcher.dispatchPending();
    fake.answer((token, message) -> PushOutcome.delivered());

    asAdmin().delete("/api/v1/admin/events/" + plain).then().statusCode(204);
    noticeDispatcher.sendDue();

    assertTrue(sent(plain).isEmpty());
  }

  @Test
  void aNoticeIsSentOnceAndNotRetriedPerDevice() throws SQLException {
    reader();
    var event = ask(MERGE_OR_HOLD);
    dispatcher.dispatchPending();
    fake.answer((token, message) -> new PushOutcome(PushOutcome.Status.TRANSIENT_FAILURE, "busy"));

    answer(owner, event, "merge");
    noticeDispatcher.sendDue();
    var firstRound = sent(event).size();
    noticeDispatcher.sendDue();

    assertEquals(1, firstRound);
    assertEquals(firstRound, sent(event).size());
    assertEquals(0, count("push_notices", event));
    // No delivery record for a notice: only the event's own push has one.
    assertEquals(List.of("DELIVERED", "DELIVERED").size(), records(event, "outcome").size());
  }

  private int count(String table, UUID event) throws SQLException {
    try (var connection = dataSource.getConnection();
        var statement =
            connection.prepareStatement("SELECT count(*) FROM " + table + " WHERE event_id = ?")) {
      statement.setObject(1, event);
      try (var rows = statement.executeQuery()) {
        rows.next();
        return rows.getInt(1);
      }
    }
  }

  private void makeRetriesDue(UUID event) {
    try (var connection = dataSource.getConnection();
        var statement =
            connection.prepareStatement(
                "UPDATE push_retries SET next_attempt_at = now() - interval '1 minute'"
                    + " WHERE event_id = ?")) {
      statement.setObject(1, event);
      statement.executeUpdate();
    } catch (SQLException e) {
      throw new IllegalStateException(e);
    }
  }
}
