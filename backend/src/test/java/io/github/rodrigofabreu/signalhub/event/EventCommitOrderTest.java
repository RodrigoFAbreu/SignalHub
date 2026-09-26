package io.github.rodrigofabreu.signalhub.event;

import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.github.rodrigofabreu.signalhub.event.EventApiTest.EVENTS;
import static io.github.rodrigofabreu.signalhub.event.EventApiTest.MINIMAL_EVENT;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.github.rodrigofabreu.signalhub.TestProducers;
import io.github.rodrigofabreu.signalhub.producer.ProducerIdentity;
import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import jakarta.inject.Inject;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.Test;

/**
 * Events become visible in listing order, so a client that stops paging at the newest event it
 * already had never misses one: open item O1 of the v1.0 readiness checklist.
 */
@QuarkusTest
class EventCommitOrderTest {

  /** How long the first publication stays uncommitted unless the test ends it sooner. */
  private static final long HOLD_SECONDS = 2;

  @Inject EventService events;

  @Test
  void anEventPublishedWhileAnotherIsUncommittedIsVisibleOnlyAfterIt() throws Exception {
    var registered = TestProducers.register("commit-order");
    var producer = new ProducerIdentity(registered.id(), registered.name());
    var request =
        new CreateEventRequest(null, Category.INFO, Severity.LOW, "Slow", null, null, null);
    var slowCreated = new CountDownLatch(1);
    var release = new CountDownLatch(1);
    try (var pool = Executors.newSingleThreadExecutor()) {
      // A publication that has taken its creation time but not committed yet, as if its commit
      // were slow.
      var slow =
          pool.submit(
              () ->
                  QuarkusTransaction.requiringNew()
                      .call(
                          () -> {
                            var published = events.create(producer, request, null);
                            slowCreated.countDown();
                            release.await(HOLD_SECONDS, TimeUnit.SECONDS);
                            return published.event();
                          }));
      assertTrue(slowCreated.await(30, TimeUnit.SECONDS));

      String fastId =
          TestProducers.asProducer(registered.apiKey())
              .contentType(ContentType.JSON)
              .body(MINIMAL_EVENT)
              .post(EVENTS)
              .then()
              .statusCode(201)
              .extract()
              .path("id");
      // Read before releasing the slow publication: once the fast one is visible, so is the slow.
      List<String> listed =
          asAdmin()
              .queryParam("producerId", registered.id())
              .get(EVENTS)
              .then()
              .statusCode(200)
              .extract()
              .path("items.id");
      release.countDown();
      var slowEvent = slow.get(30, TimeUnit.SECONDS);

      assertEquals(List.of(fastId, slowEvent.id().toString()), listed);
      Instant fastCreatedAt = events.find(UUID.fromString(fastId)).orElseThrow().createdAt();
      assertTrue(fastCreatedAt.isAfter(slowEvent.createdAt()));
    }
  }
}
