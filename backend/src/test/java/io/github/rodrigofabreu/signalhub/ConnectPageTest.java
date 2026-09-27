package io.github.rodrigofabreu.signalhub;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.startsWith;
import static org.junit.jupiter.api.Assertions.assertFalse;

import io.quarkus.test.junit.QuarkusTest;
import java.util.regex.Pattern;
import org.junit.jupiter.api.Test;

/** The operator's Connect page: a static page for pairing codes on the backend's own port. */
@QuarkusTest
class ConnectPageTest {

  private static final Pattern ASSET = Pattern.compile("(?:src|href)=\"([^\"]+)\"");

  @Test
  void thePageIsServed() {
    given()
        .get("/connect/")
        .then()
        .statusCode(200)
        .contentType(startsWith("text/html"))
        .body(containsString("<title>Connect a device - SignalHub</title>"));
  }

  @Test
  void thePageRunsOnlyItsOwnScriptsAndIsNeverFramedOrCached() {
    given()
        .get("/connect/")
        .then()
        .header("Content-Security-Policy", containsString("default-src 'none'"))
        .header("Content-Security-Policy", containsString("script-src 'self'"))
        .header("Content-Security-Policy", containsString("frame-ancestors 'none'"))
        .header("X-Frame-Options", equalTo("DENY"))
        .header("Referrer-Policy", equalTo("no-referrer"))
        .header("Cache-Control", equalTo("no-store"));
  }

  @Test
  void everyScriptAndStylesheetOfThePageIsServed() {
    // Catches a QR library version in the page that no longer matches the pom's.
    var page = given().get("/connect/").then().extract().asString();
    var assets = ASSET.matcher(page).results().map(match -> match.group(1)).toList();
    assertFalse(assets.isEmpty());
    for (var asset : assets) {
      var path = asset.startsWith("/") ? asset : "/connect/" + asset;
      given().get(path).then().statusCode(200);
    }
  }

  @Test
  void thePageHasNoInlineScript() {
    // The Content-Security-Policy would block it: every script is a file.
    var page = given().get("/connect/").then().extract().asString();
    assertFalse(Pattern.compile("<script(?![^>]*\\bsrc=)").matcher(page).find());
  }
}
