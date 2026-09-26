package io.github.rodrigofabreu.signalhub;

import io.github.rodrigofabreu.signalhub.producer.AdminToken;
import io.quarkus.runtime.StartupEvent;
import io.quarkus.runtime.configuration.ConfigUtils;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import jakarta.inject.Inject;
import java.util.Optional;
import org.eclipse.microprofile.config.Config;
import org.jboss.logging.Logger;

/**
 * Logs the release and the effective configuration once at startup, so an operator can tell from
 * the log which release, database, features and resources a running service uses. It names
 * settings, never their secret values: no admin token, database password, or credentials passed in
 * the database URL.
 */
@ApplicationScoped
class StartupDiagnostics {

  private static final Logger LOG = Logger.getLogger(StartupDiagnostics.class);

  private static final long MIB = 1024 * 1024;

  private final Config config;
  private final AdminToken adminToken;
  private final BuildInfo buildInfo;

  @Inject
  StartupDiagnostics(Config config, AdminToken adminToken, BuildInfo buildInfo) {
    this.config = config;
    this.adminToken = adminToken;
    this.buildInfo = buildInfo;
  }

  void logSummary(@Observes StartupEvent event) {
    LOG.info(summary());
  }

  String summary() {
    var runtime = Runtime.getRuntime();
    var jsonLogs =
        config.getOptionalValue("quarkus.log.console.json.enabled", Boolean.class).orElse(false);
    return String.join(
        "; ",
        buildInfo.describe(),
        "Configuration: profile " + String.join(",", ConfigUtils.getProfiles()),
        "database "
            + value("quarkus.datasource.jdbc.url")
                .map(StartupDiagnostics::redactedDatabaseUrl)
                .orElse("not configured")
            + value("quarkus.datasource.username").map(user -> " as " + user).orElse(""),
        "management API " + (adminToken.enabled() ? "enabled" : "disabled"),
        "FCM credentials file "
            + value("signalhub.push.fcm.credentials-file").orElse("not set (no fcm provider)"),
        "push dispatch every " + config.getValue("signalhub.push.dispatch.interval", String.class),
        "event retention "
            + value("signalhub.events.retention").orElse("off (events are kept forever)"),
        "JSON logs " + (jsonLogs ? "on" : "off"),
        "Java "
            + Runtime.version()
            + ", "
            + runtime.availableProcessors()
            + " CPUs, max heap "
            + runtime.maxMemory() / MIB
            + " MiB");
  }

  private Optional<String> value(String property) {
    return config.getOptionalValue(property, String.class).filter(value -> !value.isBlank());
  }

  /**
   * The database URL without what could carry credentials: its parameters ({@code ?password=...})
   * and user information ({@code //user:password@host}).
   */
  static String redactedDatabaseUrl(String url) {
    var withoutParameters = url.split("\\?", 2)[0];
    return withoutParameters.replaceFirst("//[^/]*@", "//");
  }
}
