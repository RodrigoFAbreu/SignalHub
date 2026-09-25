package io.github.rodrigofabreu.signalhub;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;

/** Flyway owns the schema; Hibernate must never create or change tables. */
@QuarkusTest
class SchemaManagementTest {

  @Inject Flyway flyway;

  @ConfigProperty(name = "quarkus.hibernate-orm.schema-management.strategy")
  String hibernateSchemaStrategy;

  @Test
  void flywayMigratedTheDatabaseAtStartup() {
    assertEquals(0, flyway.info().pending().length, "no migration may be left pending");
    assertTrue(flyway.validateWithResult().validationSuccessful, "applied migrations must match");
  }

  @Test
  void flywayReadsMigrationsFromTheConventionalLocation() {
    var locations = flyway.getConfiguration().getLocations();
    assertEquals(1, locations.length);
    assertEquals("classpath:db/migration", locations[0].getDescriptor());
    assertTrue(flyway.getConfiguration().isValidateMigrationNaming());
  }

  @Test
  void hibernateDoesNotManageTheSchema() {
    assertEquals("none", hibernateSchemaStrategy);
  }
}
