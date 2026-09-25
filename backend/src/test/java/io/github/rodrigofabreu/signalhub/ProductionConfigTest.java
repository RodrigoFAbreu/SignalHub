package io.github.rodrigofabreu.signalhub;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import io.smallrye.config.EnvConfigSource;
import io.smallrye.config.PropertiesConfigSource;
import io.smallrye.config.SmallRyeConfig;
import io.smallrye.config.SmallRyeConfigBuilder;
import java.io.IOException;
import java.util.HashMap;
import java.util.Map;
import java.util.NoSuchElementException;
import org.junit.jupiter.api.Test;

/**
 * Checks how application.properties resolves in the prod profile, where every database setting must
 * come from the environment. Runs without Quarkus or a database.
 */
class ProductionConfigTest {

  /** Environment variable → the Quarkus property it supplies. */
  private static final Map<String, String> DATABASE_VARIABLES =
      Map.of(
          "SIGNALHUB_DB_URL", "quarkus.datasource.jdbc.url",
          "SIGNALHUB_DB_USERNAME", "quarkus.datasource.username",
          "SIGNALHUB_DB_PASSWORD", "quarkus.datasource.password");

  @Test
  void databaseSettingsComeFromTheEnvironment() throws IOException {
    var env = new HashMap<String, String>();
    DATABASE_VARIABLES.keySet().forEach(name -> env.put(name, "value of " + name));
    var config = prodConfig(env);

    DATABASE_VARIABLES.forEach(
        (name, property) ->
            assertEquals("value of " + name, config.getValue(property, String.class)));
  }

  @Test
  void databaseSettingsHaveNoDefaults() throws IOException {
    var config = prodConfig(Map.of());

    DATABASE_VARIABLES.forEach(
        (name, property) ->
            assertThrows(
                NoSuchElementException.class,
                () -> config.getValue(property, String.class),
                name + " must be required in prod"));
  }

  @Test
  void schemaIsManagedOnlyByFlyway() throws IOException {
    var config = prodConfig(Map.of());

    assertEquals(true, config.getValue("quarkus.flyway.migrate-at-start", Boolean.class));
    assertEquals(
        "none", config.getValue("quarkus.hibernate-orm.schema-management.strategy", String.class));
  }

  private static SmallRyeConfig prodConfig(Map<String, String> env) throws IOException {
    var properties =
        ProductionConfigTest.class.getClassLoader().getResource("application.properties");
    // Same ordinals as Quarkus: environment variables override application.properties.
    return new SmallRyeConfigBuilder()
        .withProfile("prod")
        .withSources(new PropertiesConfigSource(properties, 250))
        .withSources(new EnvConfigSource(env, 300))
        .build();
  }
}
