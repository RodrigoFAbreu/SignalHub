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

/**
 * The operator's admin page: a static page for devices, pairing codes, producers and events on the
 * backend's port.
 */
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
    // Links to the page's own sections (#devices) are not files.
    var assets =
        ASSET
            .matcher(page)
            .results()
            .map(match -> match.group(1))
            .filter(asset -> !asset.startsWith("#"))
            .toList();
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

  @Test
  void thePageAsksWhetherTheCodeShownWasUsedAndThenStartsOver() {
    var script = given().get("/admin/admin.js").then().statusCode(200).extract().asString();
    // Only while a code is shown: polling starts with it and stops when it expires or is used.
    assertTrue(script.contains("poller = setInterval(() => check(pairing), POLL_MS);"));
    assertTrue(script.contains("const POLL_MS = 2500;"));
    assertTrue(
        Pattern.compile(
                "if \\(left === 0\\) \\{\\s*clearInterval\\(timer\\);\\s*clearInterval\\(poller\\);")
            .matcher(script)
            .find());
    assertTrue(script.contains("status = await call(\"GET\", `${PAIRINGS}/${pairing.id}`);"));
    // Used: a toast names the device, the code goes, the form is reset and the list read again.
    assertTrue(
        Pattern.compile(
                "if \\(current !== pairing \\|\\| status\\.state !== \"REDEEMED\"\\) return;\\s*"
                    + "connected\\(status\\.client\\);")
            .matcher(script)
            .find());
    assertTrue(
        Pattern.compile(
                "function connected\\(client\\) \\{\\s*clearInterval\\(timer\\);\\s*"
                    + "clearInterval\\(poller\\);\\s*current = null;\\s*"
                    + "\\$\\(\"pairing\"\\)\\.hidden = true;\\s*\\$\\(\"link\"\\)\\.value = \"\";\\s*"
                    + "\\$\\(\"create\"\\)\\.reset\\(\\);\\s*"
                    + "toast\\(`\"\\$\\{client\\.name\\}\" connected with the pairing code\\.`\\);\\s*"
                    + "refresh\\(\\);")
            .matcher(script)
            .find());
    // The name is set as text, never as HTML.
    assertTrue(script.contains("$(\"toast\").textContent = text;"));
    var page = given().get("/admin/").then().extract().asString();
    assertTrue(page.contains("<p id=\"toast\" class=\"toast\" role=\"status\" hidden></p>"));
  }

  @Test
  void thePageHasSectionsKeptInItsAddress() {
    var page = given().get("/admin/").then().extract().asString();
    assertTrue(page.contains("<a href=\"#devices\" data-section=\"devices\">Devices</a>"));
    assertTrue(page.contains("<a href=\"#producers\" data-section=\"producers\">Producers</a>"));
    assertTrue(page.contains("<a href=\"#events\" data-section=\"events\">Events</a>"));
    assertTrue(page.contains("<div id=\"section-devices\" data-section=\"devices\">"));
    assertTrue(page.contains("<div id=\"section-producers\" data-section=\"producers\" hidden>"));
    assertTrue(page.contains("<div id=\"section-events\" data-section=\"events\" hidden>"));
    var script = given().get("/admin/admin.js").then().statusCode(200).extract().asString();
    assertTrue(script.contains("const SECTIONS = [\"devices\", \"producers\", \"events\"];"));
    // The fragment names the section, Devices when it names none, so a reload stays on it; Events
    // may name an event too (#events/<id>).
    assertTrue(script.contains("const [first, eventId] = location.hash.slice(1).split(\"/\");"));
    assertTrue(
        script.contains(
            "const name = SECTIONS.find((section) => first === section) || SECTIONS[0];"));
    assertTrue(script.contains("if (name === \"events\") return showEvents(eventId);"));
    assertTrue(
        Pattern.compile(
                "window\\.addEventListener\\(\"hashchange\", \\(\\) => \\{\\s*"
                    + "if \\(token\\) showSection\\(\\);")
            .matcher(script)
            .find());
  }

  @Test
  void theAdminTokenAndProducerKeysAreNeverStoredAndNothingIsRenderedAsHtml() {
    var script = given().get("/admin/admin.js").then().statusCode(200).extract().asString();
    for (var forbidden :
        new String[] {
          "localStorage",
          "sessionStorage",
          "indexedDB",
          "document.cookie",
          "innerHTML",
          "outerHTML",
          "insertAdjacentHTML",
          "document.write"
        }) {
      assertFalse(script.contains(forbidden), forbidden);
    }
    // A new key is shown in a field once, and cleared when the operator is done with it.
    assertTrue(script.contains("$(\"new-key-value\").value = issued.apiKey;"));
    assertTrue(
        Pattern.compile("function hideKey\\(\\) \\{\\s*\\$\\(\"new-key-value\"\\)\\.value = \"\";")
            .matcher(script)
            .find());
    var page = given().get("/admin/").then().extract().asString();
    assertTrue(page.contains("This key is shown only now"));
  }

  @Test
  void thePageManagesProducersWithTheManagementApi() {
    var script = given().get("/admin/admin.js").then().statusCode(200).extract().asString();
    assertTrue(script.contains("const PRODUCERS = \"/api/v1/admin/producers\";"));
    assertTrue(
        script.contains(
            "const issued = await call(\"POST\", PRODUCERS, { name: $(\"producer-name\").value.trim() });"));
    assertTrue(script.contains("showKey(await call(\"POST\", `${PRODUCERS}/${p.id}/keys`))"));
    // Revoking a key and disabling a producer each ask first.
    assertTrue(
        Pattern.compile(
                "if \\(!confirm\\(question\\)\\) return;\\s*changeProducer\\(\\(\\) =>"
                    + " call\\(\"POST\", `\\$\\{PRODUCERS\\}/\\$\\{p\\.id\\}/keys/\\$\\{key\\.id\\}/revoke`\\)\\);")
            .matcher(script)
            .find());
    assertTrue(
        Pattern.compile(
                "function disable\\(p\\) \\{\\s*if \\(!confirm\\([^;]*\\)\\) return;\\s*"
                    + "changeProducer\\(\\(\\) => call\\(\"POST\", `\\$\\{PRODUCERS\\}/\\$\\{p\\.id\\}/disable`\\)\\);")
            .matcher(script)
            .find());
    assertTrue(script.contains("call(\"POST\", `${PRODUCERS}/${p.id}/enable`)"));
    // Revoked keys offer nothing; the others a Revoke button.
    assertTrue(
        Pattern.compile(
                "if \\(key\\.revokedAt\\) \\{\\s*text\\.append\\([^;]*\\);\\s*\\} else \\{\\s*item\\.append\\(button\\(\"Revoke\","
                    + " \\(\\) => revokeKey\\(p, key\\), \"danger\"\\)\\);")
            .matcher(script)
            .find());
    // A producer that went quiet stands out; a disabled one is not expected to publish.
    assertTrue(script.contains("const QUIET_DAYS = 7;"));
    assertTrue(
        Pattern.compile(
                "function quiet\\(producer\\) \\{\\s*if \\(producer\\.disabledAt\\) return false;\\s*"
                    + "return !producer\\.lastEventAt \\|\\| Date\\.now\\(\\) - Date\\.parse\\(producer\\.lastEventAt\\) > QUIET_DAYS \\* DAY_MS;")
            .matcher(script)
            .find());
  }

  @Test
  void thePageBrowsesEventsWithTheListingAPageAtATime() {
    var script = given().get("/admin/admin.js").then().statusCode(200).extract().asString();
    assertTrue(script.contains("const EVENTS = \"/api/v1/events\";"));
    // The app inbox's filters, each only when chosen, and the page's cursor.
    for (var filter :
        new String[] {
          "producerId: \"filter-producer\"",
          "category: \"filter-category\"",
          "severity: \"filter-severity\"",
          "read: \"filter-read\""
        }) {
      assertTrue(script.contains(filter), filter);
    }
    assertTrue(script.contains("if ($(id).value) query.set(name, $(id).value);"));
    assertTrue(script.contains("if (cursor) query.set(\"cursor\", cursor);"));
    assertTrue(script.contains("const page = await call(\"GET\", `${EVENTS}?${query}`);"));
    // Older follows the listing's cursor; Newer goes back to the page before; a filter starts over.
    assertTrue(
        Pattern.compile(
                "\\$\\(\"older-events\"\\)\\.addEventListener\\(\"click\", \\(\\) => \\{\\s*"
                    + "eventPages\\.push\\(nextEventCursor\\);")
            .matcher(script)
            .find());
    assertTrue(
        Pattern.compile(
                "\\$\\(\"newer-events\"\\)\\.addEventListener\\(\"click\", \\(\\) => \\{\\s*"
                    + "eventPages\\.pop\\(\\);")
            .matcher(script)
            .find());
    assertTrue(
        Pattern.compile(
                "\\$\\(id\\)\\.addEventListener\\(\"change\", \\(\\) => \\{\\s*"
                    + "eventPages = \\[null\\];")
            .matcher(script)
            .find());
    assertTrue(script.contains("$(\"older-events\").disabled = !nextEventCursor;"));
    var page = given().get("/admin/").then().extract().asString();
    for (var control :
        new String[] {
          "<select id=\"filter-producer\">",
          "<option value=\"ACTION_REQUIRED\">Action required</option>",
          "<option value=\"CRITICAL\">Critical</option>",
          "<option value=\"false\">Unread only</option>",
          "<button type=\"button\" id=\"older-events\" class=\"secondary\">Older</button>"
        }) {
      assertTrue(page.contains(control), control);
    }
  }

  @Test
  void anEventOpensByItsIdAndIsMarkedReadOrUnread() {
    var script = given().get("/admin/admin.js").then().statusCode(200).extract().asString();
    // Only a canonical ID from the address becomes a request path.
    assertTrue(script.contains("const one = EVENT_ID.test(eventId || \"\");"));
    assertTrue(script.contains("renderEvent(await call(\"GET\", `${EVENTS}/${eventId}`));"));
    assertTrue(script.contains("link.href = `#events/${event.id}`;"));
    assertTrue(
        script.contains(
            "renderEvent(await call(event.readAt ? \"DELETE\" : \"PUT\","
                + " `${EVENTS}/${event.id}/read`));"));
    assertTrue(
        script.contains(
            "$(\"toggle-read\").textContent = event.readAt ? \"Mark as unread\" : \"Mark as read\";"));
  }

  @Test
  void anEventIsShownAsTextAndItsLinkOnlyOpensInANewTab() {
    var script = given().get("/admin/admin.js").then().statusCode(200).extract().asString();
    // Every field is text; the metadata is formatted JSON, as text too.
    assertTrue(script.contains("$(\"event-title\").textContent = event.title;"));
    assertTrue(script.contains("$(\"event-message\").textContent = event.message || \"\";"));
    assertTrue(
        script.contains(
            "$(\"event-metadata\").textContent = JSON.stringify(event.metadata, null, 2);"));
    // A link is clickable only as http or https, opens in a new tab that cannot reach back to the
    // page and gets no referrer; the page itself never follows it.
    assertTrue(script.contains("const WEB_LINK = /^https?:\\/\\//i;"));
    assertTrue(
        Pattern.compile(
                "if \\(!WEB_LINK\\.test\\(url\\)\\) \\{\\s*cell\\.textContent = url;\\s*return cell;")
            .matcher(script)
            .find());
    assertTrue(
        Pattern.compile(
                "link\\.href = url;\\s*link\\.target = \"_blank\";\\s*"
                    + "link\\.rel = \"noopener noreferrer\";")
            .matcher(script)
            .find());
    for (var forbidden :
        new String[] {"window.open", "location.assign", "location.replace", "location.href"}) {
      assertFalse(script.contains(forbidden), forbidden);
    }
  }

  @ParameterizedTest
  @ValueSource(strings = {"/connect", "/connect/", "/connect/connect.js"})
  void theConnectPageOfEarlierReleasesIsGone(String path) {
    given().redirects().follow(false).get(path).then().statusCode(404);
  }
}
