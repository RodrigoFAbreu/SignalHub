package io.github.rodrigofabreu.signalhub;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.startsWith;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.test.junit.QuarkusTest;
import java.util.regex.Pattern;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/** The operator's admin page: a static page for devices and pairing codes on the backend's port. */
@QuarkusTest
class AdminPageTest {

  private static final Pattern ASSET = Pattern.compile("(?:src|href)=\"([^\"]+)\"");

  @Test
  void thePageIsServed() {
    given()
        .get("/admin/")
        .then()
        .statusCode(200)
        .contentType(startsWith("text/html"))
        .body(containsString("<title>Admin - SignalHub</title>"));
  }

  @ParameterizedTest
  @ValueSource(strings = {"/admin/", "/admin/admin.js", "/admin/admin.css"})
  void thePageRunsOnlyItsOwnScriptsAndIsNeverFramedOrCached(String path) {
    given()
        .get(path)
        .then()
        .statusCode(200)
        .header("Content-Security-Policy", containsString("default-src 'none'"))
        .header("Content-Security-Policy", containsString("script-src 'self'"))
        .header("Content-Security-Policy", containsString("connect-src 'self'"))
        .header("Content-Security-Policy", containsString("frame-ancestors 'none'"))
        .header("X-Frame-Options", equalTo("DENY"))
        .header("Referrer-Policy", equalTo("no-referrer"))
        .header("Cache-Control", equalTo("no-store"))
        .header("X-Content-Type-Options", equalTo("nosniff"));
  }

  @Test
  void everyScriptAndStylesheetOfThePageIsServed() {
    // Catches a QR library version in the page that no longer matches the pom's.
    var page = given().get("/admin/").then().extract().asString();
    var assets = ASSET.matcher(page).results().map(match -> match.group(1)).toList();
    assertFalse(assets.isEmpty());
    for (var asset : assets) {
      var path = asset.startsWith("/") ? asset : "/admin/" + asset;
      given().get(path).then().statusCode(200);
    }
  }

  @Test
  void thePageHasNoInlineScript() {
    // The Content-Security-Policy would block it: every script is a file.
    var page = given().get("/admin/").then().extract().asString();
    assertFalse(Pattern.compile("<script(?![^>]*\\bsrc=)").matcher(page).find());
  }

  @Test
  void thePageDeletesOnlyRevokedDevicesAfterAConfirmation() {
    // No browser runs in the tests; this pins what the page does with the management API.
    var script = given().get("/admin/admin.js").then().statusCode(200).extract().asString();
    var remove =
        Pattern.compile(
            "function remove\\(client\\) \\{\\s*if \\(!confirm\\([^;]*\\)\\) return;\\s*"
                + "change\\(\\(\\) => call\\(\"DELETE\", `\\$\\{CLIENTS\\}/\\$\\{client\\.id\\}`\\)\\);");
    assertTrue(remove.matcher(script).find());
    assertTrue(
        Pattern.compile(
                "if \\(client\\.revokedAt\\) \\{\\s*actions\\.append\\(button\\(\"Delete\","
                    + " \\(\\) => remove\\(client\\), \"danger\"\\)\\);\\s*\\} else \\{")
            .matcher(script)
            .find());
    // A deletion answers 204 with no body.
    assertTrue(script.contains("response.status === 204 ? null : response.json()"));
  }

  @ParameterizedTest
  @ValueSource(strings = {"/connect", "/connect/", "/connect/connect.js"})
  void theConnectPageOfEarlierReleasesIsGone(String path) {
    given().redirects().follow(false).get(path).then().statusCode(404);
  }
}
