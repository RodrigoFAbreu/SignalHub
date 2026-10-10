package io.github.rodrigofabreu.signalhub.push;

import static io.github.rodrigofabreu.signalhub.TestClients.CLIENT;
import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.restassured.RestAssured.given;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.github.rodrigofabreu.signalhub.TestClients;
import io.github.rodrigofabreu.signalhub.TestUsers;
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
 * The pushes a user's devices and the admins' devices get when a device of that user pairs (with a
 * code from the operator or from a device), or is revoked from a device, with the fake provider.
 * Other users' devices get none.
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
  void theUsersDevicesAndTheAdminsAreToldWhenADevicePairsAndNoOneElse() throws Exception {
    var admin = clientWithTarget("{}");
    var user = TestUsers.create("pairing-notice-user", "MOD");
    var userDevice = deviceWithTarget(user.id(), "User's phone");
    var stranger = deviceWithTarget(TestUsers.create("pairing-notice-other", "MOD").id(), "Other");

    var paired = pair("Borrowed laptop", user.id());
    notifier.awaitSent(Duration.ofSeconds(10));

    for (var token : List.of(admin, userDevice)) {
      var sent = sentTo(token);
      assertEquals(1, sent.size());
      var message = sent.get(0);
      assertEquals("New device paired", message.title());
      assertEquals(
          "\"Borrowed laptop\" can now read your SignalHub events. If you did not pair it,"
              + " revoke it.",
          message.body());
      assertEquals(
          Map.of("notice", "client-paired", "clientId", paired.toString()), message.data());
    }
    // Another user's devices learn nothing about this user's.
    assertTrue(sentTo(stranger).isEmpty());
  }

  @Test
  void theNoticeSaysWhenTheNewDeviceIsAnAdmin() throws Exception {
    var phone = clientWithTarget("{}");
    var user = TestUsers.create("pairing-notice-admin", "ADMIN");

    var paired = pair("Second admin", user.id());
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
  void theNoticeNamesTheDeviceThatCreatedTheCode() throws Exception {
    var phone = clientWithTarget("{}");
    var admin = adminWithTarget("Anna's phone");
    var user = TestUsers.create("pairing-notice-by-device", "BASIC");

    String code =
        asClient(admin.key())
            .contentType(ContentType.JSON)
            .body(Map.of("name", "Borrowed tablet", "userId", user.id().toString()))
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
  void theUsersDevicesAndTheAdminsAreToldWhenADeviceRevokesAnother() throws Exception {
    var phone = clientWithTarget("{}");
    var admin = adminWithTarget("Anna's phone");
    var target = TestClients.registerAs("MOD", "Old tablet");
    var targetToken = "notice-" + UUID.randomUUID();
    setTarget(target.clientKey(), targetToken);
    var sibling = deviceWithTarget(target.userId(), "Target's other device");
    var stranger = deviceWithTarget(TestUsers.create("revoke-notice-other", "MOD").id(), "Other");

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
    assertEquals(List.of(expected), sentTo(sibling));
    assertTrue(sentTo(stranger).isEmpty());
    // Revoking removed its push target, so the revoked device is not told.
    assertTrue(sentTo(targetToken).isEmpty());
  }

  @Test
  void nothingIsSentWhenADeviceChangesNothingOrIsRefused() throws Exception {
    var phone = clientWithTarget("{}");
    var admin = adminWithTarget("Idle admin");
    var otherAdmin = TestClients.registerAs("ADMIN", "Other admin");
    var gone = TestClients.registerAs("MOD", "Gone");
    asAdmin().post(TestClients.ADMIN + "/" + gone.id() + "/revoke").then().statusCode(200);
    var basic = TestClients.registerAs("BASIC", "Basic");

    asClient(admin.key())
        .post(CLIENT + "/devices/" + otherAdmin.id() + "/admin")
        .then()
        .statusCode(409);
    asClient(admin.key()).post(CLIENT + "/devices/" + gone.id() + "/revoke").then().statusCode(200);
    asClient(admin.key())
        .post(CLIENT + "/devices/" + otherAdmin.id() + "/revoke")
        .then()
        .statusCode(409);
    asClient(basic.clientKey())
        .post(CLIENT + "/devices/" + gone.id() + "/revoke")
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
    var target = TestClients.registerAs("MOD", "Laptop");
    fake.answer(
        (token, message) -> new PushOutcome(PushOutcome.Status.TRANSIENT_FAILURE, "provider down"));

    asClient(admin.key())
        .post(CLIENT + "/devices/" + target.id() + "/revoke")
        .then()
        .statusCode(200)
        .body("revokedAt", org.hamcrest.Matchers.notNullValue());
    notifier.awaitSent(Duration.ofSeconds(10));

    assertEquals(1, sentTo(phone).size());
  }

  /** An admin device with a push target. */
  private record Admin(UUID id, String key, String token) {}

  private static Admin adminWithTarget(String name) {
    var admin = TestClients.registerAs("ADMIN", name);
    var token = "notice-" + UUID.randomUUID();
    setTarget(admin.clientKey(), token);
    return new Admin(admin.id(), admin.clientKey(), token);
  }

  /** Pairs a device of the owner through the API, as the app does, and returns its client ID. */
  private static UUID pair(String name) {
    return pair(name, null);
  }

  private static UUID pair(String name, UUID userId) {
    var body = new java.util.LinkedHashMap<String, Object>();
    body.put("name", name);
    if (userId != null) {
      body.put("userId", userId.toString());
    }
    String code =
        asAdmin()
            .contentType(ContentType.JSON)
            .body(body)
            .post("/api/v1/admin/pairings")
            .then()
            .statusCode(201)
            .extract()
            .path("code");
    return redeem(code);
  }

  /** A device of the user with a push target; returns the target. */
  private static String deviceWithTarget(UUID userId, String name) {
    var device = TestClients.registerFor(userId, name);
    var token = "notice-" + UUID.randomUUID();
    setTarget(device.clientKey(), token);
    return token;
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
