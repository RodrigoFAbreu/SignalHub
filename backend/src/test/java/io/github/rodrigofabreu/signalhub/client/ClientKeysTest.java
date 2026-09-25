package io.github.rodrigofabreu.signalhub.client;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.Base64;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

class ClientKeysTest {

  private static final UUID ID = UUID.fromString("01997d5e-8a3c-7b1e-9f2a-4c6d8e0f1a2b");

  @Test
  void keyHasTheDocumentedFormat() {
    var key = ClientKeys.generate(ID);

    assertTrue(key.matches("shck1_01997d5e8a3c7b1e9f2a4c6d8e0f1a2b_[A-Za-z0-9_-]{43}"), key);
    assertEquals(82, key.length());
    assertEquals(32, Base64.getUrlDecoder().decode(key.substring(39)).length);
  }

  @Test
  void everyKeyIsDifferent() {
    assertNotEquals(ClientKeys.generate(ID), ClientKeys.generate(ID));
  }

  @Test
  void theClientIdRoundTrips() {
    assertEquals(Optional.of(ID), ClientKeys.clientIdOf(ClientKeys.generate(ID)));
  }

  @ParameterizedTest
  @ValueSource(
      strings = {
        "",
        "shck1_",
        // A producer key is not a client key.
        "shpk1_01997d5e8a3c7b1e9f2a4c6d8e0f1a2b_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "shck1_01997D5E8A3C7B1E9F2A4C6D8E0F1A2B_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "shck1_01997d5e8a3c7b1e9f2a4c6d8e0f1a2b_AAAA",
        "shck1_01997d5e8a3c7b1e9f2a4c6d8e0f1a2b_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
      })
  void malformedKeysHaveNoClientId(String key) {
    assertEquals(Optional.empty(), ClientKeys.clientIdOf(key));
  }
}
