package io.github.rodrigofabreu.signalhub;

import io.quarkus.flyway.FlywayConfigurationCustomizer;
import jakarta.inject.Singleton;
import java.util.Arrays;
import java.util.List;
import java.util.stream.Stream;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.MigrationInfo;
import org.flywaydb.core.api.MigrationState;
import org.flywaydb.core.api.callback.Callback;
import org.flywaydb.core.api.callback.Context;
import org.flywaydb.core.api.callback.Event;
import org.flywaydb.core.api.configuration.FluentConfiguration;

/**
 * Refuses to start on a database that a newer release has migrated, saying what to do instead: its
 * code was not written for that schema. Flyway's validation refuses too, but advises {@code
 * repair}, which would delete the newer release's migrations from the schema history and leave its
 * schema changes in place.
 *
 * <p>The check runs as a Flyway callback before validation and before the startup migration (in
 * case validation is turned off), so this release changes nothing in such a database.
 */
@Singleton
class SchemaVersionGuard implements FlywayConfigurationCustomizer, Callback {

  @Override
  public void customize(FluentConfiguration configuration) {
    var callbacks = Stream.concat(Arrays.stream(configuration.getCallbacks()), Stream.of(this));
    configuration.callbacks(callbacks.toArray(Callback[]::new));
  }

  @Override
  public boolean supports(Event event, Context context) {
    return event == Event.BEFORE_VALIDATE || event == Event.BEFORE_MIGRATE;
  }

  @Override
  public boolean canHandleInTransaction(Event event, Context context) {
    return true;
  }

  @Override
  public void handle(Event event, Context context) {
    check(new Flyway(context.getConfiguration()).info().all());
  }

  @Override
  public String getCallbackName() {
    return getClass().getSimpleName();
  }

  static void check(MigrationInfo[] migrations) {
    List<String> unknown =
        Arrays.stream(migrations)
            .filter(
                migration ->
                    migration.getState() == MigrationState.FUTURE_SUCCESS
                        || migration.getState() == MigrationState.FUTURE_FAILED)
            .map(migration -> migration.getVersion().getVersion())
            .toList();
    if (!unknown.isEmpty()) {
      throw new IllegalStateException(
          "The database was migrated by a newer SignalHub release (migrations "
              + String.join(", ", unknown)
              + " are unknown to this release). Start that release or a newer one, or restore a"
              + " backup taken before the upgrade: see docs/deployment.md#rolling-back");
    }
  }
}
