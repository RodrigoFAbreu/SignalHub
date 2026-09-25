package io.github.rodrigofabreu.signalhub;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.hasKey;

import io.quarkus.test.junit.QuarkusTest;
import org.junit.jupiter.api.Test;

@QuarkusTest
class OpenApiTest {

  @Test
  void describesTheServiceIncludingHealthEndpoints() {
    given()
        .queryParam("format", "json")
        .when()
        .get("/q/openapi")
        .then()
        .statusCode(200)
        .body("info.title", equalTo("SignalHub API"))
        .body("paths", hasKey("/q/health/live"))
        .body("paths", hasKey("/q/health/ready"));
  }
}
