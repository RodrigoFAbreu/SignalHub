package io.github.rodrigofabreu.signalhub.producer;

import io.quarkus.runtime.Startup;
import jakarta.inject.Singleton;
import java.util.Optional;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;

/**
 * The operator's token for the management API (producers and clients), from {@code
 * SIGNALHUB_ADMIN_TOKEN}; it may also read the event listing. Without it the management API is
 * disabled and only client keys read events. Checked at startup so a weak token stops the service
 * instead of protecting it poorly.
 */
@Startup
@Singleton
public final class AdminToken {

  static final int MIN_LENGTH = 32;

  private static final Logger LOG = Logger.getLogger(AdminToken.class);

  // Only the hash is kept, so comparison is constant-time whatever the presented token's length.
  private final Optional<byte[]> hash;

  AdminToken(@ConfigProperty(name = "signalhub.admin.token") Optional<String> token) {
    check(token);
    this.hash = token.map(ApiKeys::hash);
    if (token.isEmpty()) {
      LOG.info("Management API disabled: SIGNALHUB_ADMIN_TOKEN is not set");
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

  public boolean enabled() {
    return hash.isPresent();
  }

  public boolean matches(String presented) {
    return hash.isPresent() && ApiKeys.hashesMatch(ApiKeys.hash(presented), hash.get());
  }
}
