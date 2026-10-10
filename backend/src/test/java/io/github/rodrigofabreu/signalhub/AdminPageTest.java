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
    assertTrue(page.contains("<a href=\"#users\" data-section=\"users\">Users</a>"));
    assertTrue(page.contains("<a href=\"#producers\" data-section=\"producers\">Producers</a>"));
    assertTrue(page.contains("<a href=\"#events\" data-section=\"events\">Events</a>"));
    assertTrue(page.contains("<a href=\"#status\" data-section=\"status\">Status</a>"));
    assertTrue(page.contains("<div id=\"section-devices\" data-section=\"devices\">"));
    assertTrue(page.contains("<div id=\"section-users\" data-section=\"users\" hidden>"));
    assertTrue(page.contains("<div id=\"section-producers\" data-section=\"producers\" hidden>"));
    assertTrue(page.contains("<div id=\"section-events\" data-section=\"events\" hidden>"));
    assertTrue(page.contains("<div id=\"section-status\" data-section=\"status\" hidden>"));
    var script = given().get("/admin/admin.js").then().statusCode(200).extract().asString();
    assertTrue(
        script.contains(
            "const SECTIONS = [\"devices\", \"users\", \"producers\", \"events\", \"status\"];"));
    // The fragment names the section, Devices when it names none, so a reload stays on it; Events
    // may name an event too (#events/<id>).
    assertTrue(script.contains("const [first, eventId] = location.hash.slice(1).split(\"/\");"));
    assertTrue(
        script.contains(
            "const name = SECTIONS.find((section) => first === section) || SECTIONS[0];"));
    assertTrue(script.contains("if (name === \"events\") return showEvents(eventId);"));
    assertTrue(script.contains("if (name === \"status\") return refreshStatus();"));
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
  void thePageManagesUsersWithTheManagementApiAndAsksBeforeWhatCannotBeUndone() {
    var script = given().get("/admin/admin.js").then().statusCode(200).extract().asString();
    assertTrue(script.contains("const USERS = \"/api/v1/admin/users\";"));
    // Inviting, renaming, setting the role (admin included) and revoking go through the API.
    assertTrue(
        script.contains(
            "await call(\"POST\", USERS, { name: $(\"invite-name\").value.trim(), role:"
                + " $(\"invite-role\").value });"));
    assertTrue(script.contains("call(\"PATCH\", `${USERS}/${user.id}`, { role })"));
    assertTrue(script.contains("call(\"PATCH\", `${USERS}/${user.id}`, { name: name.trim() })"));
    // Making a user an admin and revoking a user each ask first.
    assertTrue(
        Pattern.compile(
                "if \\(!confirm\\(question\\)\\) return;\\s*"
                    + "changeUser\\(\\(\\) => call\\(\"PATCH\", `\\$\\{USERS\\}/\\$\\{user\\.id\\}`, \\{ role \\}\\)\\);")
            .matcher(script)
            .find());
    assertTrue(
        Pattern.compile(
                "if \\(!confirm\\(question\\)\\) return;\\s*"
                    + "changeUser\\(\\(\\) => call\\(\"POST\", `\\$\\{USERS\\}/\\$\\{user\\.id\\}/revoke`\\)\\);")
            .matcher(script)
            .find());
    // A device is connected to a user: the pairing names the user, and no admin flag is sent.
    assertTrue(script.contains("call(\"POST\", PAIRINGS, { name: name.trim(), userId: user.id })"));
    assertFalse(script.contains("admin: $(\"pair-admin\")"));
    // The role is only ever changed from this page, through the admin token.
    var page = given().get("/admin/").then().extract().asString();
    assertTrue(page.contains("Making someone an admin"));
    assertTrue(page.contains("id=\"invite-role\""));
  }

  @Test
  void thePageShowsWhoOwnsAProducerAndWhoSeesIt() {
    var script = given().get("/admin/admin.js").then().statusCode(200).extract().asString();
    assertTrue(script.contains("fact(\"Owner\", p.owner.name);"));
    assertTrue(script.contains("fact(\"User\", `${client.user.name}"));
    assertTrue(script.contains("call(\"PATCH\", `${PRODUCERS}/${p.id}`, { allowedUserIds })"));
    assertTrue(script.contains("{ visibility: toPublic ? \"PUBLIC\" : \"PRIVATE\" }"));
    var page = given().get("/admin/").then().extract().asString();
    assertTrue(page.contains("id=\"producer-owner\""));
    assertTrue(page.contains("id=\"producer-visibility\""));
    assertTrue(page.contains("id=\"pair-user\""));
  }

  @Test
  void thePageManagesProducersWithTheManagementApi() {
    var script = given().get("/admin/admin.js").then().statusCode(200).extract().asString();
    assertTrue(script.contains("const PRODUCERS = \"/api/v1/admin/producers\";"));
    // A producer is created for an owner, private or public.
    assertTrue(
        Pattern.compile(
                "const issued = await call\\(\"POST\", PRODUCERS, \\{\\s*"
                    + "name: \\$\\(\"producer-name\"\\)\\.value\\.trim\\(\\),\\s*"
                    + "ownerId: \\$\\(\"producer-owner\"\\)\\.value,\\s*"
                    + "visibility: \\$\\(\"producer-visibility\"\\)\\.value,")
            .matcher(script)
            .find());
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

  @Test
  void anEventShowsItsDeliveriesOneLinePerDeviceAsText() {
    var script = given().get("/admin/admin.js").then().statusCode(200).extract().asString();
    // Read with the admin token once the event is shown, and again on Refresh.
    assertTrue(
        script.contains(
            "renderDeliveries((await call(\"GET\","
                + " `${ADMIN_EVENTS}/${eventId}/deliveries`)).items);"));
    assertTrue(
        Pattern.compile(
                "renderEvent\\(await call\\(\"GET\", `\\$\\{EVENTS\\}/\\$\\{eventId\\}`\\)\\);"
                    + "\\s*\\} catch \\(e\\) \\{\\s*showError\\(\"event-error\", e\\.message\\);"
                    + "\\s*return;\\s*\\}\\s*await refreshDeliveries\\(eventId\\);")
            .matcher(script)
            .find());
    // One line per device, grouped by its ID, named by the device's name set as text; the rest of
    // the line, the outcome and the provider's reason, is appended as text too.
    assertTrue(
        script.contains("if (!byDevice.has(record.clientId)) byDevice.set(record.clientId, []);"));
    assertTrue(script.contains("element(\"strong\", null, last.clientName),"));
    assertTrue(script.contains("`: ${outcome(last)}, ${time(last.at)} (${ago(last.at)})`,"));
    assertTrue(script.contains("return record.detail ? `${text} (${record.detail})` : text;"));
    var page = given().get("/admin/").then().extract().asString();
    for (var control :
        new String[] {
          "<button type=\"button\" id=\"refresh-deliveries\" class=\"secondary\">Refresh</button>",
          "<ul id=\"event-deliveries\" class=\"deliveries\"></ul>",
          "<p id=\"deliveries-error\" class=\"error\" role=\"alert\" hidden></p>"
        }) {
      assertTrue(page.contains(control), control);
    }
  }

  @Test
  void eventsAreDeletedOnlyAfterAConfirmationStatingTheDryRunsCount() {
    var script = given().get("/admin/admin.js").then().statusCode(200).extract().asString();
    assertTrue(script.contains("const ADMIN_EVENTS = \"/api/v1/admin/events\";"));
    assertTrue(script.contains("const DELETE_EVENTS = \"/api/v1/admin/events/delete\";"));
    // A selection and the Delete events form: a dry run first, its count in the confirmation, and
    // only then the same request without the dry run.
    assertTrue(
        Pattern.compile(
                "const \\{ count \\} = await call\\(\"POST\", DELETE_EVENTS, \\{ \\.\\.\\.request,"
                    + " dryRun: true \\}\\);\\s*"
                    + "if \\(count === 0\\) \\{[^}]*\\}\\s*"
                    + "if \\(!confirm\\(question\\(count\\)\\)\\) return false;\\s*"
                    + "const deleted = await call\\(\"POST\", DELETE_EVENTS, request\\);")
            .matcher(script)
            .find());
    assertTrue(script.contains("deleteEvents(\n      { ids },"));
    assertTrue(script.contains("if (producer.value) request.producerId = producer.value;"));
    assertTrue(
        script.contains(
            "if (day) request.createdBefore = new Date(`${day}T00:00`).toISOString();"));
    // One event: a confirmation naming it, then back to the list.
    assertTrue(
        Pattern.compile(
                "if \\(!confirm\\([^;]*\\)\\) return;\\s*showError\\(\"event-error\", null\\);\\s*"
                    + "try \\{\\s*await call\\(\"DELETE\", `\\$\\{ADMIN_EVENTS\\}/\\$\\{event\\.id\\}`\\);")
            .matcher(script)
            .find());
    assertTrue(script.contains("location.hash = \"#events\";"));
    // A selection is only of the events shown: a page read again starts with none.
    assertTrue(
        Pattern.compile("\\$\\(\"newer-events\"\\)\\.disabled = true;\\s*selected = new Set\\(\\);")
            .matcher(script)
            .find());
    var page = given().get("/admin/").then().extract().asString();
    for (var control :
        new String[] {
          "<button type=\"button\" id=\"delete-selected\" class=\"danger\" disabled>Delete"
              + " selected</button>",
          "<button type=\"button\" id=\"delete-event\" class=\"danger\">Delete</button>",
          "<form id=\"delete-events\" autocomplete=\"off\" aria-labelledby=\"delete-events-title\">",
          "<select id=\"delete-producer\">",
          "<input id=\"delete-before\" type=\"date\" />"
        }) {
      assertTrue(page.contains(control), control);
    }
  }

  @Test
  void aTestEventIsSentAsAnEnabledProducerAndLinkedOnceSent() {
    var script = given().get("/admin/admin.js").then().statusCode(200).extract().asString();
    // Through the management API, as the producer chosen; only enabled producers are offered.
    assertTrue(
        script.contains(
            "sent = await call(\"POST\", `${PRODUCERS}/${$(\"send-producer\").value}/events`,"
                + " testEvent());"));
    assertTrue(
        script.contains(
            "[\"send-producer\", \"Choose a producer\", producers.filter((p) => !p.disabledAt)],"));
    // The fields a producer sends, the optional ones only when filled in; metadata only as a JSON
    // object.
    assertTrue(
        Pattern.compile(
                "category: \\$\\(\"send-category\"\\)\\.value,\\s*"
                    + "severity: \\$\\(\"send-severity\"\\)\\.value,\\s*"
                    + "title: \\$\\(\"send-title\"\\)\\.value\\.trim\\(\\),")
            .matcher(script)
            .find());
    assertTrue(script.contains("if (value) request[name] = value;"));
    assertTrue(script.contains("if (metadata) request.metadata = jsonObject(metadata);"));
    assertTrue(
        script.contains(
            "if (value === null || typeof value !== \"object\" || Array.isArray(value)) {"));
    // Once sent: a link to the event in the Events section, where it can be deleted, set as text.
    assertTrue(
        Pattern.compile(
                "const link = element\\(\"a\", null, \"Open it\"\\);\\s*"
                    + "link\\.href = `#events/\\$\\{sent\\.id\\}`;\\s*"
                    + "\\$\\(\"send-event-result\"\\)\\.replaceChildren\\(")
            .matcher(script)
            .find());
    var page = given().get("/admin/").then().extract().asString();
    // Defaults that make a push likely to arrive.
    for (var control :
        new String[] {
          "<form id=\"send-event\" autocomplete=\"off\" aria-labelledby=\"send-event-title\">",
          "<select id=\"send-producer\" required>",
          "<option value=\"ACTION_REQUIRED\" selected>Action required</option>",
          "<option value=\"HIGH\" selected>High</option>",
          "<input id=\"send-title\" type=\"text\" required maxlength=\"200\" value=\"Test event\" />",
          "<textarea id=\"send-metadata\" rows=\"3\" spellcheck=\"false\"></textarea>",
          "<button type=\"submit\">Send test event</button>"
        }) {
      assertTrue(page.contains(control), control);
    }
  }

  @Test
  void theStatusIsReadFromWhatExistsAndTheManagementApi() {
    var script = given().get("/admin/admin.js").then().statusCode(200).extract().asString();
    assertTrue(script.contains("const STATUS = \"/api/v1/admin/status\";"));
    assertTrue(script.contains("const INFO = \"/q/info\";"));
    assertTrue(script.contains("const HEALTH = \"/q/health\";"));
    // Every part at once, each shown or said to be unreadable on its own; the latest event from
    // the listing and the devices' last push results from the device list.
    assertTrue(
        Pattern.compile(
                "await Promise\\.allSettled\\(\\[\\s*probe\\(INFO\\),\\s*probe\\(HEALTH\\),\\s*"
                    + "call\\(\"GET\", STATUS\\),\\s*call\\(\"GET\", CLIENTS\\),\\s*"
                    + "call\\(\"GET\", `\\$\\{EVENTS\\}\\?limit=1`\\),\\s*\\]\\);")
            .matcher(script)
            .find());
    // /q/ needs no token, so the page sends it none; health that is down answers 503 with its
    // checks, which the page still reads.
    assertTrue(script.contains("response = await fetch(path, { cache: \"no-store\" });"));
    assertTrue(
        Pattern.compile(
                "try \\{\\s*return await response\\.json\\(\\);\\s*\\} catch \\{\\s*"
                    + "throw new Error\\(`SignalHub answered \\$\\{response\\.status\\}\\.`\\);")
            .matcher(script)
            .find());
    // A device counts while its latest result is a failure; a revoked one never does.
    assertTrue(
        Pattern.compile(
                "if \\(client\\.revokedAt \\|\\| !lastFailure\\) return false;\\s*"
                    + "return !lastSuccess \\|\\| Date\\.parse\\(lastFailure\\.at\\) >"
                    + " Date\\.parse\\(lastSuccess\\.at\\);")
            .matcher(script)
            .find());
    // A failure that is not one of SignalHub's own errors, such as a database that is down, is
    // said by its status, never shown as an empty error.
    assertTrue(
        script.contains(
            "if (body.title) return details ? `${body.title}: ${details}` : body.title;"));
    assertTrue(
        Pattern.compile(
                "\\} catch \\{\\s*// Not JSON[^\\n]*\\s*\\}\\s*(//[^\\n]*\\s*)*"
                    + "return `SignalHub answered \\$\\{response\\.status\\}\\.`;")
            .matcher(script)
            .find());
    // Values from the server are text: each fact is an element given its text.
    assertTrue(script.contains("const cell = element(\"dd\", null, value);"));
    assertTrue(script.contains("$(\"status-facts\").replaceChildren(...facts);"));
    var page = given().get("/admin/").then().extract().asString();
    for (var control :
        new String[] {
          "<button type=\"button\" id=\"refresh-status\" class=\"secondary\">Refresh</button>",
          "<dl id=\"status-facts\" class=\"facts\"></dl>",
          "<ul id=\"failing-devices\" class=\"keys\"></ul>"
        }) {
      assertTrue(page.contains(control), control);
    }
  }

  @ParameterizedTest
  @ValueSource(strings = {"/connect", "/connect/", "/connect/connect.js"})
  void theConnectPageOfEarlierReleasesIsGone(String path) {
    given().redirects().follow(false).get(path).then().statusCode(404);
  }
}
