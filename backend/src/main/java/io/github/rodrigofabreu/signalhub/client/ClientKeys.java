package io.github.rodrigofabreu.signalhub.client;

import java.nio.ByteBuffer;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.HexFormat;
import java.util.Optional;
import java.util.UUID;
import java.util.regex.Pattern;

/**
 * Client keys: {@code shck1_<client id>_<secret>}, built like producer API keys but with their own
 * prefix ("SignalHub client key", version 1), so the two kinds are never confused and a scanner can
 * tell them apart. The client ID is not secret; it selects the one stored record to check. The
 * secret is 32 bytes from {@link SecureRandom}, base64url without padding (43 chars). Only SHA-256
 * of the complete key is stored.
 */
final class ClientKeys {

  static final String PREFIX = "shck1_";

  private static final int SECRET_BYTES = 32;
  private static final Pattern FORMAT =
      Pattern.compile(Pattern.quote(PREFIX) + "([0-9a-f]{32})_[A-Za-z0-9_-]{43}");
  private static final SecureRandom RANDOM = new SecureRandom();
  private static final HexFormat HEX = HexFormat.of();

  private ClientKeys() {}

  /** A new random key for the given client. */
  static String generate(UUID clientId) {
    var secret = new byte[SECRET_BYTES];
    RANDOM.nextBytes(secret);
    var id =
        ByteBuffer.allocate(16)
            .putLong(clientId.getMostSignificantBits())
            .putLong(clientId.getLeastSignificantBits())
            .array();
    return PREFIX
        + HEX.formatHex(id)
        + "_"
        + Base64.getUrlEncoder().withoutPadding().encodeToString(secret);
  }

  /** The client ID of a well-formed key; empty for anything else. Never inspects the secret. */
  static Optional<UUID> clientIdOf(String key) {
    var matcher = FORMAT.matcher(key);
    if (!matcher.matches()) {
      return Optional.empty();
    }
    var id = ByteBuffer.wrap(HEX.parseHex(matcher.group(1)));
    return Optional.of(new UUID(id.getLong(), id.getLong()));
  }
}
