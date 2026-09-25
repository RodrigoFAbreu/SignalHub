package io.github.rodrigofabreu.signalhub;

import io.quarkus.runtime.StartupEvent;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import java.util.Optional;
import org.eclipse.microprofile.config.inject.ConfigProperty;

/**
 * Refuses to start without a database. Quarkus otherwise deactivates a datasource that has no URL,
 * which silently skips migrations and makes readiness report UP with no database behind it.
 */
@ApplicationScoped
class DatabaseRequirement {

  void requireDatabaseUrl(
      @Observes StartupEvent event,
      @ConfigProperty(name = "quarkus.datasource.jdbc.url") Optional<String> url) {
    check(url);
  }

  static void check(Optional<String> url) {
    if (url.isEmpty()) {
      throw new IllegalStateException(
          "No database configured: set SIGNALHUB_DB_URL, SIGNALHUB_DB_USERNAME and"
              + " SIGNALHUB_DB_PASSWORD (see .env.example)");
    }
  }
}
