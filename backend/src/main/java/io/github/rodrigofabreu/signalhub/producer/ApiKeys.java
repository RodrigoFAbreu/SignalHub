package io.github.rodrigofabreu.signalhub.producer;

import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.HexFormat;
import java.util.Optional;
import java.util.UUID;
import java.util.regex.Pattern;

/**
 * Producer API keys: {@code shpk1_<key id>_<secret>}.
 *
 * <ul>
 *   <li>{@code shpk1_} names the format ("SignalHub producer key", version 1), so a key is
 *       recognizable in logs or secret scanners and a future format can coexist.
 *   <li>The key ID is the {@code producer_api_keys} primary key as 32 lowercase hex digits. It is
 *       not secret; it selects the one stored record to check.
 *   <li>The secret is 32 bytes from {@link SecureRandom}, base64url without padding (43 chars).
 * </ul>
 *
 * <p>Only SHA-256 of the complete key is stored. A slow password hash would add nothing: with 256
 * random bits there is nothing to brute-force, and it would cost CPU on every event.
 */
final class ApiKeys {

  static final String PREFIX = "shpk1_";
  static final int HASH_BYTES = 32;

  private static final int SECRET_BYTES = 32;
  private static final Pattern FORMAT =
      Pattern.compile(Pattern.quote(PREFIX) + "([0-9a-f]{32})_[A-Za-z0-9_-]{43}");
  private static final SecureRandom RANDOM = new SecureRandom();
  private static final HexFormat HEX = HexFormat.of();

  private ApiKeys() {}

  /** A new random key for the given key ID. */
  static String generate(UUID keyId) {
    var secret = new byte[SECRET_BYTES];
    RANDOM.nextBytes(secret);
    return PREFIX
        + HEX.formatHex(toBytes(keyId))
        + "_"
        + Base64.getUrlEncoder().withoutPadding().encodeToString(secret);
  }

  /** The key ID of a well-formed key; empty for anything else. Never inspects the secret. */
  static Optional<UUID> keyIdOf(String key) {
    var matcher = FORMAT.matcher(key);
    if (!matcher.matches()) {
      return Optional.empty();
    }
    var id = ByteBuffer.wrap(HEX.parseHex(matcher.group(1)));
    return Optional.of(new UUID(id.getLong(), id.getLong()));
  }

  static byte[] hash(String key) {
    try {
      return MessageDigest.getInstance("SHA-256").digest(key.getBytes(StandardCharsets.UTF_8));
    } catch (NoSuchAlgorithmException e) {
      throw new IllegalStateException("every Java platform provides SHA-256", e);
    }
  }

  /** Constant-time comparison, so response timing does not reveal how much of a hash matched. */
  static boolean hashesMatch(byte[] presented, byte[] stored) {
    return MessageDigest.isEqual(presented, stored);
  }

  private static byte[] toBytes(UUID id) {
    return ByteBuffer.allocate(16)
        .putLong(id.getMostSignificantBits())
        .putLong(id.getLeastSignificantBits())
        .array();
  }
}
