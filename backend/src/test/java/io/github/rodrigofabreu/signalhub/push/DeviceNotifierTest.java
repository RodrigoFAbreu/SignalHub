package io.github.rodrigofabreu.signalhub.push;

import static io.github.rodrigofabreu.signalhub.TestClients.CLIENT;
import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.equalTo;
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

/**
 * The pushes the owner's devices get when a device pairs (with a code from the operator or from an
 * admin device), or is made an admin or revoked from an admin device, with the fake provider.
 */
@QuarkusTest
class DeviceNotifierTest {

  @Inject DeviceNotifier notifier;
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
  void theNoticeSaysWhenTheNewDeviceIsAnAdmin() throws Exception {
    var phone = clientWithTarget("{}");

    var paired = pair("Second admin", true);
    notifier.awaitSent(Duration.ofSeconds(10));

    var sent = sentTo(phone);
    assertEquals(1, sent.size());
    var message = sent.get(0);
    assertEquals("New admin device paired", message.title());
    assertEquals(
        "\"Second admin\" is an admin device and can now read your SignalHub events. If you did"
            + " not pair it, revoke it.",
        message.body());
    assertEquals(Map.of("notice", "client-paired", "clientId", paired.toString()), message.data());
  }

  @Test
  void theNoticeNamesTheAdminDeviceThatCreatedTheCode() throws Exception {
    var phone = clientWithTarget("{}");
    var admin = adminWithTarget("Anna's phone");

    String code =
        asClient(admin.key())
            .contentType(ContentType.JSON)
            .body(Map.of("name", "Borrowed tablet"))
            .post(CLIENT + "/pairings")
            .then()
            .statusCode(201)
            .extract()
            .path("code");
    var paired = redeem(code);
    notifier.awaitSent(Duration.ofSeconds(10));

    var expected =
        new PushMessage(
            "New device paired",
            "\"Borrowed tablet\" can now read your SignalHub events. \"Anna's phone\" created its"
                + " pairing code. If this was not you, revoke both on the admin page.",
            Map.of(
                "notice",
                "client-paired",
                "clientId",
                paired.toString(),
                "byClientId",
                admin.id().toString()));
    assertEquals(List.of(expected), sentTo(phone));
    // The device that created the code is told too: its key may be in someone else's hands.
    assertEquals(List.of(expected), sentTo(admin.token()));
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

  @Test
  void theOwnersDevicesAreToldWhenADeviceMakesAnotherAnAdmin() throws Exception {
    var phone = clientWithTarget("{}");
    var admin = adminWithTarget("Anna's phone");
    var target = TestClients.register("Tablet");

    asClient(admin.key())
        .post(CLIENT + "/devices/" + target.id() + "/admin")
        .then()
        .statusCode(200);
    notifier.awaitSent(Duration.ofSeconds(10));

    var expected =
        new PushMessage(
            "Device made an admin",
            "\"Anna's phone\" made \"Tablet\" an admin device. If this was not you, revoke both"
                + " on the admin page.",
            Map.of(
                "notice",
                "client-made-admin",
                "clientId",
                target.id().toString(),
                "byClientId",
                admin.id().toString()));
    assertEquals(List.of(expected), sentTo(phone));
    // The device that did it is told too: its key may be in someone else's hands.
    assertEquals(List.of(expected), sentTo(admin.token()));
  }

  @Test
  void theOwnersDevicesAreToldWhenADeviceRevokesAnother() throws Exception {
    var phone = clientWithTarget("{}");
    var admin = adminWithTarget("Anna's phone");
    var target = TestClients.register("Old tablet");
    var targetToken = "notice-" + UUID.randomUUID();
    setTarget(target.clientKey(), targetToken);

    asClient(admin.key())
        .post(CLIENT + "/devices/" + target.id() + "/revoke")
        .then()
        .statusCode(200);
    notifier.awaitSent(Duration.ofSeconds(10));

    var expected =
        new PushMessage(
            "Device revoked",
            "\"Anna's phone\" revoked \"Old tablet\". If this was not you, revoke \"Anna's"
                + " phone\" on the admin page.",
            Map.of(
                "notice",
                "client-revoked",
                "clientId",
                target.id().toString(),
                "byClientId",
                admin.id().toString()));
    assertEquals(List.of(expected), sentTo(phone));
    assertEquals(List.of(expected), sentTo(admin.token()));
    // Revoking removed its push target, so the revoked device is not told.
    assertTrue(sentTo(targetToken).isEmpty());
  }

  @Test
  void nothingIsSentWhenADeviceChangesNothingOrIsRefused() throws Exception {
    var phone = clientWithTarget("{}");
    var admin = adminWithTarget("Idle admin");
    var otherAdmin = TestClients.registerAdmin("Other admin");
    var gone = TestClients.register("Gone");
    asAdmin().post(TestClients.ADMIN + "/" + gone.id() + "/revoke").then().statusCode(200);
    var ordinary = TestClients.register("Ordinary");

    asClient(admin.key())
        .post(CLIENT + "/devices/" + otherAdmin.id() + "/admin")
        .then()
        .statusCode(200);
    asClient(admin.key()).post(CLIENT + "/devices/" + gone.id() + "/revoke").then().statusCode(200);
    asClient(admin.key())
        .post(CLIENT + "/devices/" + otherAdmin.id() + "/revoke")
        .then()
        .statusCode(409);
    asClient(ordinary.clientKey())
        .post(CLIENT + "/devices/" + gone.id() + "/admin")
        .then()
        .statusCode(403);
    notifier.awaitSent(Duration.ofSeconds(10));

    assertTrue(sentTo(phone).isEmpty());
    assertTrue(sentTo(admin.token()).isEmpty());
  }

  @Test
  void aFailedNoticeDoesNotFailTheChange() throws Exception {
    var phone = clientWithTarget("{}");
    var admin = adminWithTarget("Admin");
    var target = TestClients.register("Laptop");
    fake.answer(
        (token, message) -> new PushOutcome(PushOutcome.Status.TRANSIENT_FAILURE, "provider down"));

    asClient(admin.key())
        .post(CLIENT + "/devices/" + target.id() + "/admin")
        .then()
        .statusCode(200)
        .body("admin", equalTo(true));
    notifier.awaitSent(Duration.ofSeconds(10));

    assertEquals(1, sentTo(phone).size());
  }

  /** An admin device with a push target. */
  private record Admin(UUID id, String key, String token) {}

  private static Admin adminWithTarget(String name) {
    var admin = TestClients.registerAdmin(name);
    var token = "notice-" + UUID.randomUUID();
    setTarget(admin.clientKey(), token);
    return new Admin(admin.id(), admin.clientKey(), token);
  }

  /** Pairs a device through the API, as the app does, and returns its client ID. */
  private static UUID pair(String name) {
    return pair(name, false);
  }

  private static UUID pair(String name, boolean admin) {
    String code =
        asAdmin()
            .contentType(ContentType.JSON)
            .body(Map.of("name", name, "admin", admin))
            .post("/api/v1/admin/pairings")
            .then()
            .statusCode(201)
            .extract()
            .path("code");
    return redeem(code);
  }

  /** Redeems a pairing code, as the app does, and returns the new client's ID. */
  private static UUID redeem(String code) {
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
