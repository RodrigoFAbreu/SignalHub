package io.github.rodrigofabreu.signalhub;

import io.quarkus.test.common.QuarkusTestResourceLifecycleManager;
import java.util.Map;
import org.testcontainers.postgresql.PostgreSQLContainer;

/**
 * A PostgreSQL container owned by one test profile, for tests that stop the database or leave extra
 * schema behind. Other tests use the shared Dev Services database.
 */
public class DedicatedPostgres implements QuarkusTestResourceLifecycleManager {

  // Quarkus runs one test profile at a time, so a single static handle is enough.
  static PostgreSQLContainer container;

  @Override
  public Map<String, String> start() {
    container = new PostgreSQLContainer("postgres:17-alpine");
    container.start();
    // An explicit URL also keeps Dev Services from starting a second database.
    return Map.of(
        "quarkus.datasource.jdbc.url", container.getJdbcUrl(),
        "quarkus.datasource.username", container.getUsername(),
        "quarkus.datasource.password", container.getPassword());
  }

  @Override
  public void stop() {
    container.stop();
  }
}
