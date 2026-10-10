package io.github.rodrigofabreu.signalhub;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.not;
import static org.hamcrest.Matchers.startsWith;
import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.test.junit.QuarkusTest;
import java.io.IOException;
import java.net.URI;
import java.util.ArrayDeque;
import java.util.LinkedHashSet;
import java.util.Set;
import java.util.regex.Pattern;
import org.junit.jupiter.api.Test;

/**
 * The users' web page: static files on the backend's port that the proxy forwards. These tests pin
 * what a browser test cannot cheaply: every file the page is made of exists, each is served with
 * the strict policy, and nothing in them names a server of anyone else's.
 */
@QuarkusTest
class AppPageTest {

  private static final Pattern HTML_REFERENCE = Pattern.compile("(?:src|href)=\"([^\"#]+)\"");
  private static final Pattern MODULE_IMPORT =
      Pattern.compile("(?:from|import)\\s*\\(?\\s*\"(\\.[^\"]+)\"");
  private static final Pattern CSS_URL = Pattern.compile("url\\(([^)]+)\\)");
  private static final Pattern ABSOLUTE_URL = Pattern.compile("https?://[^\\s\"')]+");

  /** The page, then what it references, then what those load. */
  private static Set<String> files() {
    var seen = new LinkedHashSet<String>();
    var queue = new ArrayDeque<String>();
    queue.add("/app/");
    while (!queue.isEmpty()) {
      var path = queue.poll();
      if (!seen.add(path)) {
        continue;
      }
      var text = given().get(path).then().statusCode(200).extract().asString();
      Pattern pattern;
      if (path.endsWith("/") || path.endsWith(".html")) {
        pattern = HTML_REFERENCE;
      } else if (path.endsWith(".css")) {
        pattern = CSS_URL;
      } else if (path.endsWith(".js") || path.endsWith(".mjs")) {
        pattern = MODULE_IMPORT;
      } else {
        continue;
      }
      var base = URI.create("http://x" + path);
      pattern
          .matcher(text)
          .results()
          .map(match -> match.group(1).replace("'", "").replace("\"", ""))
          .filter(reference -> !reference.matches("^[a-z]+:.*"))
          .forEach(reference -> queue.add(base.resolve(reference).getPath()));
    }
    return seen;
  }

  @Test
  void thePageIsServedAtItsFolder() {
    given()
        .get("/app/")
        .then()
        .statusCode(200)
        .contentType(startsWith("text/html"))
        .body(containsString("<title>SignalHub</title>"))
        .body(containsString("<script type=\"module\" src=\"js/main.js\"></script>"));
    // /app (no slash) is redirected to /app/ by the proxy; the backend serves the folder only.
  }

  @Test
  void everyFileThePageLoadsIsServed() {
    var files = files();
    // The page, its stylesheet and fonts, its icon, its modules and the QR encoder.
    assertTrue(
        files.containsAll(
            Set.of(
                "/app/",
                "/app/app.css",
                "/app/js/main.js",
                "/app/vendor/qrcode.mjs",
                "/app/fonts/fonts.css",
                "/app/icon.svg")));
    assertTrue(files.size() > 20, files.toString());
    assertTrue(files.stream().anyMatch(file -> file.endsWith(".woff2")));
  }

  @Test
  void everyFileIsServedWithThePolicyAndRevalidated() {
    for (var path : files()) {
      given()
          .get(path)
          .then()
          .statusCode(200)
          .header("Content-Security-Policy", containsString("default-src 'none'"))
          .header("Content-Security-Policy", containsString("script-src 'self'"))
          .header("Content-Security-Policy", containsString("style-src 'self'"))
          .header("Content-Security-Policy", containsString("connect-src 'self'"))
          .header("Content-Security-Policy", containsString("font-src 'self'"))
          .header("Content-Security-Policy", containsString("form-action 'none'"))
          .header("Content-Security-Policy", containsString("frame-ancestors 'none'"))
          .header("Content-Security-Policy", containsString("base-uri 'none'"))
          .header("Content-Security-Policy", containsString("object-src 'none'"))
          .header("Content-Security-Policy", not(containsString("unsafe-")))
          .header("X-Frame-Options", equalTo("DENY"))
          .header("Referrer-Policy", equalTo("no-referrer"))
          .header("Cache-Control", equalTo("no-cache"))
          .header("X-Content-Type-Options", equalTo("nosniff"));
    }
  }

  @Test
  void moduleScriptsAreServedAsJavaScript() {
    // A module script with another type is refused by the browser.
    for (var path : files()) {
      if (path.endsWith(".js") || path.endsWith(".mjs")) {
        given().get(path).then().header("Content-Type", containsString("javascript"));
      }
    }
  }

  @Test
  void thePageHasNoInlineScriptHandlerOrStyle() {
    var page = given().get("/app/").then().extract().asString();
    assertFalse(Pattern.compile("<script(?![^>]*\\bsrc=)").matcher(page).find());
    assertFalse(Pattern.compile("\\son[a-z]+\\s*=", Pattern.CASE_INSENSITIVE).matcher(page).find());
    assertFalse(Pattern.compile("\\sstyle\\s*=", Pattern.CASE_INSENSITIVE).matcher(page).find());
  }

  @Test
  void thePagesCodeNeverBuildsMarkupFromAValue() {
    var forbidden =
        Pattern.compile(
            "innerHTML|outerHTML|insertAdjacentHTML|document\\.write|\\beval\\(|new Function|setAttribute\\(\\s*[\"']style[\"']");
    for (var path : files()) {
      if (path.startsWith("/app/js/")) {
        var code = given().get(path).then().extract().asString();
        assertFalse(forbidden.matcher(code).find(), path);
      }
    }
  }

  @Test
  void nothingNamesAnotherServer() {
    // The page and its stylesheets name no address at all but the SVG namespace, which is an
    // identifier and not a request; the QR encoder only mentions its authors in comments.
    for (var path : files()) {
      if (!(path.endsWith(".html")
          || path.endsWith(".css")
          || path.endsWith(".js")
          || path.endsWith(".mjs")
          || path.endsWith("/"))) {
        continue;
      }
      var text = given().get(path).then().extract().asString();
      for (var line : text.split("\n")) {
        var found = ABSOLUTE_URL.matcher(line);
        while (found.find()) {
          var address = found.group();
          var comment =
              line.stripLeading().startsWith("//")
                  || line.stripLeading().startsWith("*")
                  || line.stripLeading().startsWith("/*");
          assertTrue(
              address.equals("http://www.w3.org/2000/svg") || comment, path + " names " + address);
        }
      }
    }
  }

  @Test
  void theBundledQrEncoderIsTheOneTheBackendDependsOn() throws IOException {
    // The admin page names the WebJar version the pom pins; the page's copy must be that file.
    var admin = given().get("/admin/").then().extract().asString();
    var version = Pattern.compile("/webjars/qrcode-generator/([0-9.]+)/").matcher(admin);
    assertTrue(version.find());
    var path =
        "/META-INF/resources/webjars/qrcode-generator/" + version.group(1) + "/dist/qrcode.mjs";
    try (var webjar = AppPageTest.class.getResourceAsStream(path)) {
      assertTrue(webjar != null, path);
      var served =
          given().get("/app/vendor/qrcode.mjs").then().statusCode(200).extract().asByteArray();
      assertArrayEquals(webjar.readAllBytes(), served);
    }
  }

  @Test
  void theLicencesOfWhatIsBundledAreServed() {
    for (var licence :
        new String[] {
          "Roboto-OFL.txt",
          "RobotoMono-OFL.txt",
          "MaterialSymbols-Apache-2.0.txt",
          "qrcode-generator-MIT.txt",
          "README.md"
        }) {
      given().get("/app/licenses/" + licence).then().statusCode(200);
    }
  }

  @Test
  void theAdminPageIsUntouchedAndKeepsItsOwnHeaders() {
    given()
        .get("/admin/")
        .then()
        .statusCode(200)
        .header("Cache-Control", equalTo("no-store"))
        .header("Content-Security-Policy", containsString("img-src 'self' blob:"));
  }
}
