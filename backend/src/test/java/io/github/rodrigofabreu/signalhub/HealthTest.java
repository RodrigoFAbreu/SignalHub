package io.github.rodrigofabreu.signalhub;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.equalTo;

import io.quarkus.test.junit.QuarkusTest;
import org.junit.jupiter.api.Test;

@QuarkusTest
class HealthTest {

  /** GPath to the status of the datasource check contributed by the Agroal extension. */
  static final String DATABASE_CHECK_STATUS =
      "checks.find { it.name == 'Database connections health check' }.status";

  @Test
  void livenessIsUp() {
    given().when().get("/q/health/live").then().statusCode(200).body("status", equalTo("UP"));
  }

  @Test
  void readinessIsUpWhenDatabaseIsReachable() {
    given()
        .when()
        .get("/q/health/ready")
        .then()
        .statusCode(200)
        .body("status", equalTo("UP"))
        .body(DATABASE_CHECK_STATUS, equalTo("UP"));
  }
}
