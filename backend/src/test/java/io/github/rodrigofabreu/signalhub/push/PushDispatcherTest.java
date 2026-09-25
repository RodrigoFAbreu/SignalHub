package io.github.rodrigofabreu.signalhub.push;

import static io.github.rodrigofabreu.signalhub.TestClients.CLIENT;
import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.nullValue;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.github.rodrigofabreu.signalhub.TestClients;
import io.github.rodrigofabreu.signalhub.client.ClientService;
import io.github.rodrigofabreu.signalhub.client.PushTarget;
import io.github.rodrigofabreu.signalhub.event.Category;
import io.github.rodrigofabreu.signalhub.event.Severity;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import jakarta.inject.Inject;
import java.time.Duration;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.Test;

/**
 * Delivery to push targets through the provider boundary, with the recording test provider in place
 * of a real one. Calls {@link PushDispatcher#deliver} directly, so each delivery has finished when
 * the call returns.
 */
@QuarkusTest
class PushDispatcherTest {

  private static final Duration NOW = Duration.ZERO;

  @Inject PushDispatcher dispatcher;
  @Inject RecordingPushProvider provider;
  @Inject ClientService clients;

  @Test
  void sendsTheMessageToEveryTargetOfItsProvider() throws InterruptedException {
    var first = registerWithTarget("dispatch-a", RecordingPushProvider.NAME, token("ok"));
    var second = registerWithTarget("dispatch-b", RecordingPushProvider.NAME, token("ok"));
    var message = message();

    dispatcher.deliver(message);

    assertEquals(message, provider.await(first.token(), message.eventId(), NOW));
    assertEquals(message, provider.await(second.token(), message.eventId(), NOW));
  }

  @Test
  void skipsTargetsOfProvidersThatAreNotAvailable() {
    var unsupported = registerWithTarget("dispatch-other", "not-available", token("ok"));

    dispatcher.deliver(message());

    assertTrue(provider.drain(unsupported.token()).isEmpty());
    asClient(unsupported.clientKey())
        .get(CLIENT)
        .then()
        .body("pushTarget.provider", equalTo("not-available"));
  }

  @Test
  void removesATargetTheProviderReportsAsInvalid() throws InterruptedException {
    var invalid =
        registerWithTarget("dispatch-invalid", RecordingPushProvider.NAME, token("invalid"));

    var message = message();

    dispatcher.deliver(message);

    provider.await(invalid.token(), message.eventId(), NOW);
    asClient(invalid.clientKey()).get(CLIENT).then().body("pushTarget", nullValue());
  }

  @Test
  void keepsTargetsThatFailedAndStillDeliversToTheOthers() throws InterruptedException {
    var failing = registerWithTarget("dispatch-fail", RecordingPushProvider.NAME, token("fail"));
    var throwing = registerWithTarget("dispatch-throw", RecordingPushProvider.NAME, token("throw"));
    var healthy = registerWithTarget("dispatch-healthy", RecordingPushProvider.NAME, token("ok"));
    var message = message();

    dispatcher.deliver(message);

    provider.await(failing.token(), message.eventId(), NOW);
    provider.await(throwing.token(), message.eventId(), NOW);
    assertEquals(message, provider.await(healthy.token(), message.eventId(), NOW));
    for (var client : List.of(failing, throwing)) {
      asClient(client.clientKey())
          .get(CLIENT)
          .then()
          .body("pushTarget.provider", equalTo(RecordingPushProvider.NAME));
    }
  }

  @Test
  void droppingAnInvalidTargetKeepsOneTheClientSetSince() {
    var client = registerWithTarget("dispatch-replaced", RecordingPushProvider.NAME, token("old"));
    setPushTarget(client.clientKey(), RecordingPushProvider.NAME, token("new"));

    clients.dropPushTarget(new PushTarget(client.id(), RecordingPushProvider.NAME, client.token()));

    asClient(client.clientKey())
        .get(CLIENT)
        .then()
        .body("pushTarget.provider", equalTo(RecordingPushProvider.NAME));
  }

  @Test
  void revokedClientsGetNoPush() {
    var client = registerWithTarget("dispatch-revoked", RecordingPushProvider.NAME, token("ok"));
    asAdmin().post(TestClients.ADMIN + "/" + client.id() + "/revoke").then().statusCode(200);

    dispatcher.deliver(message());

    assertTrue(provider.drain(client.token()).isEmpty());
  }

  @Test
  void providerNamesMustBeValidAndUnique() {
    assertEquals(Set.of("a", "b"), PushDispatcher.byName(List.of(named("b"), named("a"))).keySet());
    assertThrows(IllegalStateException.class, () -> PushDispatcher.byName(List.of(named("Fcm"))));
    assertThrows(IllegalStateException.class, () -> PushDispatcher.byName(List.of(named(null))));
    assertThrows(
        IllegalStateException.class,
        () -> PushDispatcher.byName(List.of(named("fcm"), named("fcm"))));
  }

  private record Target(UUID id, String clientKey, String token) {}

  private static Target registerWithTarget(String name, String providerName, String token) {
    var client = TestClients.register(name);
    setPushTarget(client.clientKey(), providerName, token);
    return new Target(client.id(), client.clientKey(), token);
  }

  private static void setPushTarget(String clientKey, String providerName, String token) {
    asClient(clientKey)
        .contentType(ContentType.JSON)
        .body("{\"provider\": \"" + providerName + "\", \"token\": \"" + token + "\"}")
        .put(CLIENT + "/push-target")
        .then()
        .statusCode(200);
  }

  private static String token(String outcome) {
    return outcome + "-" + UUID.randomUUID();
  }

  private static PushMessage message() {
    return new PushMessage(
        UUID.randomUUID(), Category.BLOCKED, Severity.HIGH, "Deploy blocked", "Needs approval.");
  }

  private static PushProvider named(String name) {
    return new PushProvider() {
      @Override
      public String name() {
        return name;
      }

      @Override
      public PushResult send(PushMessage message, String token) {
        return PushResult.DELIVERED;
      }
    };
  }
}
