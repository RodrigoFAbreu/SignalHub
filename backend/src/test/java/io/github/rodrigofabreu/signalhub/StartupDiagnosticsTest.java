package io.github.rodrigofabreu.signalhub;

import static org.hamcrest.MatcherAssert.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
import static org.junit.jupiter.api.Assertions.assertEquals;

import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.junit.jupiter.api.Test;

/** The configuration summary logged at startup: what it names, and what it never reveals. */
@QuarkusTest
class StartupDiagnosticsTest {

  @Inject StartupDiagnostics diagnostics;

  @ConfigProperty(name = "signalhub.admin.token")
  String adminToken;

  @Test
  void summaryNamesTheEffectiveConfiguration() {
    var summary = diagnostics.summary();

    assertThat(summary, containsString("Configuration: profile test"));
    assertThat(summary, containsString("database jdbc:postgresql://"));
    assertThat(summary, containsString("management API enabled"));
    assertThat(summary, containsString("FCM credentials file not set (no fcm provider)"));
    assertThat(summary, containsString("push dispatch every 2s"));
    assertThat(summary, containsString("event retention off (events are kept forever)"));
    assertThat(summary, containsString("JSON logs off"));
    assertThat(summary, containsString("Java " + Runtime.version().feature()));
    assertThat(summary, containsString(" MiB"));
  }

  @Test
  void summaryNeverContainsSecrets() {
    var summary = diagnostics.summary();

    assertThat(summary, not(containsString(adminToken)));
    // Dev Services' database password ("quarkus") is also the database name in the URL, so the
    // URL's redaction is checked with known values below instead.
    assertThat(summary, not(containsString("password")));
  }

  @Test
  void databaseUrlLosesParametersAndUserInformation() {
    assertEquals(
        "jdbc:postgresql://postgres:5432/signalhub",
        StartupDiagnostics.redactedDatabaseUrl("jdbc:postgresql://postgres:5432/signalhub"));
    assertEquals(
        "jdbc:postgresql://postgres:5432/signalhub",
        StartupDiagnostics.redactedDatabaseUrl(
            "jdbc:postgresql://postgres:5432/signalhub?user=signalhub&password=secret"));
    assertEquals(
        "jdbc:postgresql://postgres/signalhub",
        StartupDiagnostics.redactedDatabaseUrl("jdbc:postgresql://user:secret@postgres/signalhub"));
  }
}
