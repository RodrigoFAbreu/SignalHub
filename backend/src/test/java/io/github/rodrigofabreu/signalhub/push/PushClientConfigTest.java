package io.github.rodrigofabreu.signalhub.push;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

class PushClientConfigTest {

  private static final PushProviders WITH_FAKE = new PushProviders(List.of(new FakePushProvider()));

  @Test
  void noOptionsServeNothing() {
    assertTrue(new PushClientConfig(WITH_FAKE, List.of()).current().isEmpty());
  }

  @Test
  void optionsForAnEnabledProviderAreServed() {
    var options = options(FakePushProvider.NAME);

    assertEquals(options, new PushClientConfig(WITH_FAKE, List.of(options)).current().get());
  }

  @Test
  void optionsForAProviderThatIsNotEnabledStopStartup() {
    var e =
        assertThrows(
            IllegalStateException.class,
            () -> new PushClientConfig(WITH_FAKE, List.of(options("fcm"))));
    assertEquals(
        "Push client options are set for provider fcm, which is not enabled", e.getMessage());
  }

  @Test
  void optionsForTwoProvidersStopStartup() {
    assertThrows(
        IllegalStateException.class,
        () ->
            new PushClientConfig(
                WITH_FAKE, List.of(options(FakePushProvider.NAME), options("other"))));
  }

  private static PushClientOptions options(String provider) {
    return new PushClientOptions() {
      @Override
      public String provider() {
        return provider;
      }

      @Override
      public Map<String, String> options() {
        return Map.of("PROJECT", "p");
      }
    };
  }
}
