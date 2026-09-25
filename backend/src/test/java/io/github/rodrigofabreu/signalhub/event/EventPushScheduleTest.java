package io.github.rodrigofabreu.signalhub.event;

import static io.github.rodrigofabreu.signalhub.TestClients.CLIENT;
import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asProducer;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.github.rodrigofabreu.signalhub.TestClients;
import io.github.rodrigofabreu.signalhub.TestProducers;
import io.github.rodrigofabreu.signalhub.push.FakePushProvider;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.QuarkusTestProfile;
import io.quarkus.test.junit.TestProfile;
import io.restassured.http.ContentType;
import jakarta.inject.Inject;
import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;

/** With the scheduler on, as in production, a published event is pushed without being asked. */
@QuarkusTest
@TestProfile(EventPushScheduleTest.Profile.class)
class EventPushScheduleTest {

  @Inject FakePushProvider fake;

  @Test
  void theDispatcherRunsOnItsOwn() throws InterruptedException {
    var client = TestClients.register("scheduled");
    var token = "scheduled-" + UUID.randomUUID();
    asClient(client.clientKey())
        .contentType(ContentType.JSON)
        .body(Map.of("provider", FakePushProvider.NAME, "token", token))
        .put(CLIENT + "/push-target")
        .then()
        .statusCode(200);

    asProducer(TestProducers.register("scheduled").apiKey())
        .contentType(ContentType.JSON)
        .body(Map.of("category", "COMPLETED", "severity", "LOW", "title", "Nightly backup done"))
        .post("/api/v1/events")
        .then()
        .statusCode(201);

    var deadline = Instant.now().plus(Duration.ofSeconds(20));
    while (fake.sent().stream().noneMatch(sent -> sent.token().equals(token))
        && Instant.now().isBefore(deadline)) {
      Thread.sleep(50);
    }
    assertTrue(fake.sent().stream().anyMatch(sent -> sent.token().equals(token)));
  }

  public static class Profile implements QuarkusTestProfile {
    @Override
    public Map<String, String> getConfigOverrides() {
      return Map.of(
          "quarkus.scheduler.enabled", "true", "signalhub.push.dispatch.interval", "0.2s");
    }
  }
}
