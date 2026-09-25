package io.github.rodrigofabreu.signalhub.producer;

import io.quarkus.runtime.Startup;
import jakarta.inject.Singleton;
import java.util.Optional;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;

/**
 * The operator's token for the producer management API, from {@code SIGNALHUB_ADMIN_TOKEN}. Without
 * it the management API is disabled. Checked at startup so a weak token stops the service instead
 * of protecting it poorly.
 */
@Startup
@Singleton
final class AdminToken {

  static final int MIN_LENGTH = 32;

  private static final Logger LOG = Logger.getLogger(AdminToken.class);

  // Only the hash is kept, so comparison is constant-time whatever the presented token's length.
  private final Optional<byte[]> hash;

  AdminToken(@ConfigProperty(name = "signalhub.admin.token") Optional<String> token) {
    check(token);
    this.hash = token.map(ApiKeys::hash);
    if (token.isEmpty()) {
      LOG.info("Producer management API disabled: SIGNALHUB_ADMIN_TOKEN is not set");
    }
  }

  static void check(Optional<String> token) {
    if (token.isPresent() && token.get().length() < MIN_LENGTH) {
      throw new IllegalStateException(
          "SIGNALHUB_ADMIN_TOKEN must be at least "
              + MIN_LENGTH
              + " characters; generate one with `openssl rand -hex 32`");
    }
  }

  boolean enabled() {
    return hash.isPresent();
  }

  boolean matches(String presented) {
    return hash.isPresent() && ApiKeys.hashesMatch(ApiKeys.hash(presented), hash.get());
  }
}
