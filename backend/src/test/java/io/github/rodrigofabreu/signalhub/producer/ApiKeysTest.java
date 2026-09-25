package io.github.rodrigofabreu.signalhub.producer;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.Base64;
import java.util.HashSet;
import java.util.HexFormat;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

class ApiKeysTest {

  private static final UUID ID = UUID.fromString("3f1c0b8e-5d2a-4c7e-9b61-0a8d4e2f7c13");

  @Test
  void keyHasTheDocumentedFormat() {
    var key = ApiKeys.generate(ID);

    assertTrue(key.matches("shpk1_3f1c0b8e5d2a4c7e9b610a8d4e2f7c13_[A-Za-z0-9_-]{43}"), key);
    assertEquals(82, key.length());
  }

  @Test
  void secretCarries256RandomBits() {
    var key = ApiKeys.generate(ID);
    // Prefix (6) + key ID (32) + separator (1); the secret may itself contain '_'.
    var secret = Base64.getUrlDecoder().decode(key.substring(39));

    assertEquals(32, secret.length);
  }

  @Test
  void everyKeyIsDifferent() {
    var keys = new HashSet<String>();
    for (int i = 0; i < 1000; i++) {
      keys.add(ApiKeys.generate(ID));
    }
    assertEquals(1000, keys.size());
  }

  @Test
  void keyIdRoundTrips() {
    assertEquals(Optional.of(ID), ApiKeys.keyIdOf(ApiKeys.generate(ID)));
    var random = UUID.randomUUID();
    assertEquals(Optional.of(random), ApiKeys.keyIdOf(ApiKeys.generate(random)));
  }

  @ParameterizedTest
  @ValueSource(
      strings = {
        "",
        "shpk1_",
        "shpk1_3f1c0b8e5d2a4c7e9b610a8d4e2f7c13_",
        // Uppercase hex: every key has exactly one spelling.
        "shpk1_3F1C0B8E5D2A4C7E9B610A8D4E2F7C13_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        // Secret one character short, then one too long.
        "shpk1_3f1c0b8e5d2a4c7e9b610a8d4e2f7c13_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "shpk1_3f1c0b8e5d2a4c7e9b610a8d4e2f7c13_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "shpk2_3f1c0b8e5d2a4c7e9b610a8d4e2f7c13_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "shpk1_3f1c0b8e5d2a4c7e9b610a8d4e2f7c13_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
        " shpk1_3f1c0b8e5d2a4c7e9b610a8d4e2f7c13_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "shpk1_3f1c0b8e5d2a4c7e9b610a8d4e2f7c13_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\n"
      })
  void malformedKeysHaveNoId(String key) {
    assertEquals(Optional.empty(), ApiKeys.keyIdOf(key));
  }

  @Test
  void hashIsSha256OfTheWholeKey() {
    // FIPS 180-2 test vector.
    assertArrayEquals(
        HexFormat.of().parseHex("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
        ApiKeys.hash("abc"));
    assertEquals(ApiKeys.HASH_BYTES, ApiKeys.hash(ApiKeys.generate(ID)).length);
  }

  @Test
  void hashesMatchOnlyWhenEqual() {
    var key = ApiKeys.generate(ID);
    var other = ApiKeys.generate(ID);

    assertTrue(ApiKeys.hashesMatch(ApiKeys.hash(key), ApiKeys.hash(key)));
    assertFalse(ApiKeys.hashesMatch(ApiKeys.hash(key), ApiKeys.hash(other)));
    assertNotEquals(key, other);
  }
}
