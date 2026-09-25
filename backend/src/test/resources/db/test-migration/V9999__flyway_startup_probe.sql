-- Test-only migration used by FlywayStartupMigrationTest. Never shipped.
CREATE TABLE flyway_startup_probe (note text NOT NULL);
INSERT INTO flyway_startup_probe (note) VALUES ('applied by Flyway');
