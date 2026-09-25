package io.github.rodrigofabreu.signalhub;

import io.quarkus.runtime.LaunchMode;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.context.Initialized;
import jakarta.enterprise.event.Observes;
import java.util.Optional;
import org.eclipse.microprofile.config.ConfigProvider;

/**
 * Refuses to start without a database, naming the settings to fix. Quarkus otherwise deactivates a
 * datasource that has no URL and later fails with a message about its own properties.
 *
 * <p>The check observes container initialization so it runs before Hibernate ORM starts. Only the
 * packaged application is checked: in dev and test, Dev Services supplies the URL after this point.
 */
@ApplicationScoped
class DatabaseRequirement {

  // Read on demand rather than injected: Quarkus rejects runtime config injected this early.
  void requireDatabaseUrl(@Observes @Initialized(ApplicationScoped.class) Object event) {
    if (LaunchMode.current() == LaunchMode.NORMAL) {
      check(
          ConfigProvider.getConfig().getOptionalValue("quarkus.datasource.jdbc.url", String.class));
    }
  }

  static void check(Optional<String> url) {
    if (url.isEmpty()) {
      throw new IllegalStateException(
          "No database configured: set SIGNALHUB_DB_URL, SIGNALHUB_DB_USERNAME and"
              + " SIGNALHUB_DB_PASSWORD (see .env.example)");
    }
  }
}
