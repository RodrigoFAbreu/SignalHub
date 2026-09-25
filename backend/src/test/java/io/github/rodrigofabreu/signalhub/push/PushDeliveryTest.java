package io.github.rodrigofabreu.signalhub.push;

import static io.github.rodrigofabreu.signalhub.TestClients.ADMIN;
import static io.github.rodrigofabreu.signalhub.TestClients.CLIENT;
import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.nullValue;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.github.rodrigofabreu.signalhub.TestClients;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import jakarta.inject.Inject;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;

/** Delivery through the provider boundary, with a fake provider and real PostgreSQL. */
@QuarkusTest
class PushDeliveryTest {

  private static final PushMessage MESSAGE =
      new PushMessage("Build failed", "3 tests failed", Map.of("eventId", "e-1"));

  @Inject PushDelivery delivery;
  @Inject FakePushProvider fake;

  @BeforeEach
  void deliverByDefault() {
    fake.answer((token, message) -> PushOutcome.delivered());
  }

  @Test
  void deliversThroughTheProviderTheTargetNames() {
    var client = withTarget(FakePushProvider.NAME, "token-" + UUID.randomUUID());

    assertEquals(DeliveryResult.DELIVERED, delivery.deliver(client.id(), MESSAGE));

    assertEquals(1, fake.sent().size());
    assertEquals(client.token(), fake.sent().get(0).token());
    assertEquals(MESSAGE, fake.sent().get(0).message());
  }

  @Test
  void aClientWithoutATargetGetsNothing() {
    var client = TestClients.register("no-target");

    assertEquals(DeliveryResult.NO_TARGET, delivery.deliver(client.id(), MESSAGE));
    assertEquals(DeliveryResult.NO_TARGET, delivery.deliver(UUID.randomUUID(), MESSAGE));
    assertTrue(fake.sent().isEmpty());
  }

  @Test
  void aRevokedClientGetsNothing() {
    var client = withTarget(FakePushProvider.NAME, "revoked-" + UUID.randomUUID());
    asAdmin().post(ADMIN + "/" + client.id() + "/revoke").then().statusCode(200);

    assertEquals(DeliveryResult.NO_TARGET, delivery.deliver(client.id(), MESSAGE));
    assertTrue(fake.sent().isEmpty());
  }

  @Test
  void aTargetOfAnUnknownProviderIsUnsupported() {
    var client = withTarget("fcm", "fcm-" + UUID.randomUUID());

    assertEquals(DeliveryResult.UNSUPPORTED_PROVIDER, delivery.deliver(client.id(), MESSAGE));
    assertTrue(fake.sent().isEmpty());
    // The target is kept: a provider may be configured later.
    asClient(client.key()).get(CLIENT).then().body("pushTarget.provider", equalTo("fcm"));
  }

  @Test
  void anInvalidTargetIsRemoved() {
    var client = withTarget(FakePushProvider.NAME, "gone-" + UUID.randomUUID());
    fake.answer((token, message) -> new PushOutcome(PushOutcome.Status.INVALID_TARGET, "gone"));

    assertEquals(DeliveryResult.INVALID_TARGET, delivery.deliver(client.id(), MESSAGE));

    asClient(client.key()).get(CLIENT).then().body("pushTarget", nullValue());
    assertEquals(DeliveryResult.NO_TARGET, delivery.deliver(client.id(), MESSAGE));
  }

  @Test
  void aTargetReplacedDuringTheSendIsKept() {
    var client = withTarget(FakePushProvider.NAME, "old-" + UUID.randomUUID());
    var newToken = "new-" + UUID.randomUUID();
    fake.answer(
        (token, message) -> {
          // The app registers a fresh token while the send to the old one is in flight.
          setTarget(client.key(), FakePushProvider.NAME, newToken);
          return new PushOutcome(PushOutcome.Status.INVALID_TARGET, "gone");
        });

    assertEquals(DeliveryResult.INVALID_TARGET, delivery.deliver(client.id(), MESSAGE));

    fake.answer((token, message) -> PushOutcome.delivered());
    assertEquals(DeliveryResult.DELIVERED, delivery.deliver(client.id(), MESSAGE));
    assertEquals(newToken, fake.sent().get(0).token());
  }

  @ParameterizedTest
  @EnumSource(
      value = PushOutcome.Status.class,
      names = {"TRANSIENT_FAILURE", "PERMANENT_FAILURE"})
  void otherFailuresKeepTheTarget(PushOutcome.Status status) {
    var client = withTarget(FakePushProvider.NAME, "kept-" + UUID.randomUUID());
    fake.answer((token, message) -> new PushOutcome(status, "failed"));

    assertEquals(DeliveryResult.valueOf(status.name()), delivery.deliver(client.id(), MESSAGE));

    asClient(client.key())
        .get(CLIENT)
        .then()
        .body("pushTarget.provider", equalTo(FakePushProvider.NAME));
  }

  @Test
  void aProviderExceptionCountsAsTransient() {
    var client = withTarget(FakePushProvider.NAME, "throws-" + UUID.randomUUID());
    fake.answer(
        (token, message) -> {
          throw new IllegalStateException("provider bug");
        });

    assertEquals(DeliveryResult.TRANSIENT_FAILURE, delivery.deliver(client.id(), MESSAGE));
    asClient(client.key())
        .get(CLIENT)
        .then()
        .body("pushTarget.provider", equalTo(FakePushProvider.NAME));
  }

  private record Target(UUID id, String key, String token) {}

  private static Target withTarget(String provider, String token) {
    var client = TestClients.register("push-delivery");
    setTarget(client.clientKey(), provider, token);
    return new Target(client.id(), client.clientKey(), token);
  }

  private static void setTarget(String clientKey, String provider, String token) {
    asClient(clientKey)
        .contentType(ContentType.JSON)
        .body(Map.of("provider", provider, "token", token))
        .put(CLIENT + "/push-target")
        .then()
        .statusCode(200);
  }
}
