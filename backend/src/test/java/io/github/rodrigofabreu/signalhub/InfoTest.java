package io.github.rodrigofabreu.signalhub;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.nullValue;

import io.quarkus.test.junit.QuarkusTest;
import org.junit.jupiter.api.Test;

/** /q/info names the running release; a build the release did not make is a development build. */
@QuarkusTest
class InfoTest {

  @Test
  void aBuildOutsideTheReleaseReportsADevelopmentVersion() {
    given()
        .when()
        .get("/q/info")
        .then()
        .statusCode(200)
        .body("signalhub.version", equalTo("development"))
        .body("signalhub.revision", nullValue())
        // Quarkus's own sections that would show the source placeholder or need .git are off.
        .body("build", nullValue())
        .body("git", nullValue());
  }
}
