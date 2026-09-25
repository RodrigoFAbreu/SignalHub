package io.github.rodrigofabreu.signalhub.push;

import static io.github.rodrigofabreu.signalhub.TestClients.CLIENT;
import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static org.hamcrest.Matchers.nullValue;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.github.rodrigofabreu.signalhub.TestClients;
import io.quarkus.test.common.QuarkusTestResourceLifecycleManager;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.QuarkusTestProfile;
import io.quarkus.test.junit.TestProfile;
import io.restassured.http.ContentType;
import jakarta.inject.Inject;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * With a credentials file configured, the {@code fcm} provider is active and delivery reaches FCM,
 * here {@link FakeFcm}. Without one (every other test) it is absent.
 */
@QuarkusTest
@TestProfile(FcmDeliveryTest.Profile.class)
class FcmDeliveryTest {

  private static final PushMessage MESSAGE =
      new PushMessage("Disk almost full", "95% used", Map.of("eventId", "e-2"));

  @Inject PushDelivery delivery;
  @Inject PushProviders providers;

  FakeFcm fcm;

  @BeforeEach
  void reset() {
    fcm.reset();
  }

  @Test
  void theFcmProviderIsActive() {
    assertTrue(providers.named("fcm").isPresent());
    assertTrue(providers.named(FakePushProvider.NAME).isPresent());
  }

  @Test
  void deliversToAClientWithAnFcmTarget() {
    var client = withFcmTarget("fcm-" + UUID.randomUUID());

    assertEquals(DeliveryResult.DELIVERED, delivery.deliver(client.id(), MESSAGE));

    var message = fcm.sends().get(0).body().path("message");
    assertEquals(client.token(), message.path("token").asText());
    assertEquals("Disk almost full", message.path("notification").path("title").asText());
  }

  @Test
  void anUnregisteredTokenIsRemoved() {
    var client = withFcmTarget("gone-" + UUID.randomUUID());
    fcm.answerSends(404, FakeFcm.error(404, "NOT_FOUND", "UNREGISTERED"));

    assertEquals(DeliveryResult.INVALID_TARGET, delivery.deliver(client.id(), MESSAGE));

    asClient(client.key()).get(CLIENT).then().body("pushTarget", nullValue());
  }

  private record Target(UUID id, String key, String token) {}

  private static Target withFcmTarget(String token) {
    var client = TestClients.register("fcm-delivery");
    asClient(client.clientKey())
        .contentType(ContentType.JSON)
        .body(Map.of("provider", "fcm", "token", token))
        .put(CLIENT + "/push-target")
        .then()
        .statusCode(200);
    return new Target(client.id(), client.clientKey(), token);
  }

  public static class Profile implements QuarkusTestProfile {
    @Override
    public List<TestResourceEntry> testResources() {
      return List.of(new TestResourceEntry(FakeFcmResource.class));
    }
  }

  /** Runs {@link FakeFcm} and points the {@code fcm} provider at it. */
  public static class FakeFcmResource implements QuarkusTestResourceLifecycleManager {
    private FakeFcm fcm;

    @Override
    public Map<String, String> start() {
      fcm = new FakeFcm();
      return Map.of(
          FcmPushProvider.CREDENTIALS_FILE,
          fcm.writeCredentials().toString(),
          "signalhub.push.fcm.api-url",
          fcm.apiUrl().toString());
    }

    @Override
    public void inject(TestInjector injector) {
      injector.injectIntoFields(fcm, new TestInjector.MatchesType(FakeFcm.class));
    }

    @Override
    public void stop() {
      if (fcm != null) {
        fcm.close();
      }
    }
  }
}
