package io.github.rodrigofabreu.signalhub;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.equalTo;

import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.QuarkusTestProfile;
import io.quarkus.test.junit.TestProfile;
import java.util.List;
import org.junit.jupiter.api.Test;

/** Readiness follows the real database: stopping PostgreSQL makes the service not ready. */
@QuarkusTest
@TestProfile(DatabaseOutageTest.Profile.class)
class DatabaseOutageTest {

  @Test
  void readinessGoesDownWhenDatabaseStops() {
    given().when().get("/q/health/ready").then().statusCode(200).body("status", equalTo("UP"));

    DedicatedPostgres.container.stop();

    given()
        .when()
        .get("/q/health/ready")
        .then()
        .statusCode(503)
        .body("status", equalTo("DOWN"))
        .body(HealthTest.DATABASE_CHECK_STATUS, equalTo("DOWN"));
    given().when().get("/q/health/live").then().statusCode(200).body("status", equalTo("UP"));
  }

  public static class Profile implements QuarkusTestProfile {
    @Override
    public List<TestResourceEntry> testResources() {
      return List.of(new TestResourceEntry(DedicatedPostgres.class));
    }
  }
}
