package io.github.rodrigofabreu.signalhub.event;

import static io.github.rodrigofabreu.signalhub.TestClients.CLIENT;
import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asProducer;
import static org.junit.jupiter.api.Assertions.assertEquals;

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

/** With background dispatch on, as in production, publishing an event pushes it on its own. */
@QuarkusTest
@TestProfile(BackgroundPushDispatchTest.Profile.class)
class BackgroundPushDispatchTest {

  @Inject FakePushProvider fake;

  @Test
  void publishingAnEventPushesItWithoutFurtherAction() throws InterruptedException {
    var client = TestClients.register("background");
    var token = "background-" + UUID.randomUUID();
    asClient(client.clientKey())
        .contentType(ContentType.JSON)
        .body("{\"provider\": \"" + FakePushProvider.NAME + "\", \"token\": \"" + token + "\"}")
        .when()
        .put(CLIENT + "/push-target")
        .then()
        .statusCode(200);
    var producer = TestProducers.register("background");

    String eventId =
        asProducer(producer.apiKey())
            .contentType(ContentType.JSON)
            .body("{\"category\": \"COMPLETED\", \"severity\": \"NORMAL\", \"title\": \"Done\"}")
            .when()
            .post("/api/v1/events")
            .then()
            .statusCode(201)
            .extract()
            .path("id");

    assertEquals(1, awaitSends(token, eventId));
  }

  private long awaitSends(String token, String eventId) throws InterruptedException {
    var deadline = Instant.now().plus(Duration.ofSeconds(10));
    while (true) {
      var count =
          fake.sent().stream()
              .filter(sent -> sent.token().equals(token))
              .filter(sent -> eventId.equals(sent.message().data().get("eventId")))
              .count();
      if (count > 0 || Instant.now().isAfter(deadline)) {
        return count;
      }
      Thread.sleep(50);
    }
  }

  public static class Profile implements QuarkusTestProfile {
    @Override
    public Map<String, String> getConfigOverrides() {
      return Map.of("signalhub.push.dispatch.background", "true");
    }
  }
}
