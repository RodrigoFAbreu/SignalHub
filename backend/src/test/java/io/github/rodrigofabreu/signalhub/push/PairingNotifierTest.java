package io.github.rodrigofabreu.signalhub.push;

import static io.github.rodrigofabreu.signalhub.TestClients.CLIENT;
import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.restassured.RestAssured.given;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.github.rodrigofabreu.signalhub.TestClients;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import jakarta.inject.Inject;
import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/** The push the owner's devices get when a device pairs, with the fake provider. */
@QuarkusTest
class PairingNotifierTest {

  @Inject PairingNotifier notifier;
  @Inject FakePushProvider fake;

  @BeforeEach
  void setUp() {
    fake.answer((token, message) -> PushOutcome.delivered());
  }

  @Test
  void theOwnersDevicesAreToldWhenADevicePairs() throws Exception {
    var phone = clientWithTarget("{}");

    var paired = pair("Borrowed laptop");
    notifier.awaitSent(Duration.ofSeconds(10));

    var sent = sentTo(phone);
    assertEquals(1, sent.size());
    var message = sent.get(0);
    assertEquals("New device paired", message.title());
    assertEquals(
        "\"Borrowed laptop\" can now read your SignalHub events. If you did not pair it, revoke it.",
        message.body());
    assertEquals(Map.of("notice", "client-paired", "clientId", paired.toString()), message.data());
  }

  @Test
  void aClientWithPushesPausedIsNotTold() throws Exception {
    var paused = clientWithTarget("{\"enabled\": false}");
    // Preferences about events do not hold back a notice that is not one.
    var muted =
        clientWithTarget(
            "{\"minimumSeverity\": \"CRITICAL\", \"mutedCategories\": [\"COMPLETED\"]}");

    pair("Second phone");
    notifier.awaitSent(Duration.ofSeconds(10));

    assertTrue(sentTo(paused).isEmpty());
    assertEquals(1, sentTo(muted).size());
  }

  @Test
  void aFailedNoticeDoesNotFailThePairing() throws Exception {
    var phone = clientWithTarget("{}");
    fake.answer(
        (token, message) -> new PushOutcome(PushOutcome.Status.TRANSIENT_FAILURE, "provider down"));

    pair("Tablet");
    notifier.awaitSent(Duration.ofSeconds(10));

    // Sent once and not retried: a notice has no outbox.
    assertEquals(1, sentTo(phone).size());
  }

  @Test
  void aRevokedClientIsNotTold() throws Exception {
    var client = TestClients.register("revoked-before-pairing");
    var token = "notice-" + UUID.randomUUID();
    setTarget(client.clientKey(), token);
    asAdmin().post(TestClients.ADMIN + "/" + client.id() + "/revoke").then().statusCode(200);

    pair("After revocation");
    notifier.awaitSent(Duration.ofSeconds(10));

    assertTrue(sentTo(token).isEmpty());
  }

  /** Pairs a device through the API, as the app does, and returns its client ID. */
  private static UUID pair(String name) {
    String code =
        asAdmin()
            .contentType(ContentType.JSON)
            .body(Map.of("name", name))
            .post("/api/v1/admin/pairings")
            .then()
            .statusCode(201)
            .extract()
            .path("code");
    String id =
        given()
            .header("Authorization", "Bearer " + code)
            .post("/api/v1/pairing")
            .then()
            .statusCode(201)
            .extract()
            .path("client.id");
    return UUID.fromString(id);
  }

  private static String clientWithTarget(String preferences) {
    var client = TestClients.register("pairing-notice");
    var token = "notice-" + UUID.randomUUID();
    setTarget(client.clientKey(), token);
    asClient(client.clientKey())
        .contentType(ContentType.JSON)
        .body(preferences)
        .put(CLIENT + "/push-preferences")
        .then()
        .statusCode(200);
    return token;
  }

  private static void setTarget(String clientKey, String token) {
    asClient(clientKey)
        .contentType(ContentType.JSON)
        .body(Map.of("provider", FakePushProvider.NAME, "token", token))
        .put(CLIENT + "/push-target")
        .then()
        .statusCode(200);
  }

  private List<PushMessage> sentTo(String token) {
    return fake.sent().stream()
        .filter(sent -> sent.token().equals(token))
        .map(FakePushProvider.Sent::message)
        .toList();
  }
}
