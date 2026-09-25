package io.github.rodrigofabreu.signalhub.push;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.List;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

class PushProvidersTest {

  @Test
  void findsProvidersByName() {
    var a = provider("a");
    var providers = new PushProviders(List.of(a, provider("b.2")));

    assertEquals(a, providers.named("a").orElseThrow());
    assertTrue(providers.named("c").isEmpty());
  }

  @Test
  void noProvidersIsAValidConfiguration() {
    assertTrue(new PushProviders(List.of()).named("fcm").isEmpty());
  }

  @Test
  void twoProvidersWithOneNameStopStartup() {
    var e =
        assertThrows(
            IllegalStateException.class,
            () -> new PushProviders(List.of(provider("fcm"), provider("fcm"))));
    assertTrue(e.getMessage().contains("share a name"), e.getMessage());
  }

  @ParameterizedTest
  @ValueSource(strings = {"", "FCM", "-fcm", "f cm"})
  void aNameNoPushTargetCouldCarryStopsStartup(String name) {
    assertThrows(IllegalStateException.class, () -> new PushProviders(List.of(provider(name))));
  }

  @Test
  void aNameLongerThanATargetProviderStopsStartup() {
    assertThrows(
        IllegalStateException.class, () -> new PushProviders(List.of(provider("p".repeat(51)))));
  }

  private static PushProvider provider(String name) {
    return new PushProvider() {
      @Override
      public String name() {
        return name;
      }

      @Override
      public PushOutcome send(String token, PushMessage message) {
        return PushOutcome.delivered();
      }
    };
  }
}
