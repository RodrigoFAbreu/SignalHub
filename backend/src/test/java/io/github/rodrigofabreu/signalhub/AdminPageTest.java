package io.github.rodrigofabreu.signalhub;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.not;
import static org.hamcrest.Matchers.startsWith;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.test.junit.QuarkusTest;
import java.net.URI;
import java.util.ArrayDeque;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Pattern;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/**
 * The operator's admin page: plain HTML, CSS and ES modules on the backend's port, with the layout,
 * tokens and wording of the approved drawings. These tests pin what a browser test cannot cheaply:
 * every file the page is made of is served with the strict policy, nothing is stored or rendered as
 * markup, nothing names another server, and the pages' calls to the management API are the ones
 * documented. How the page looks and behaves is tested in a headless browser (web-tests/).
 */
@QuarkusTest
class AdminPageTest {

  private static final Pattern HTML_REFERENCE = Pattern.compile("(?:src|href)=\"([^\"#]+)\"");
  private static final Pattern MODULE_IMPORT =
      Pattern.compile("(?:from|import)\\s*\\(?\\s*\"(\\.[^\"]+)\"");
  private static final Pattern CSS_URL = Pattern.compile("url\\(([^)]+)\\)");

  private static String source(String path) {
    return given().get("/admin/js/" + path).then().statusCode(200).extract().asString();
  }

  private static String page() {
    return given().get("/admin/").then().statusCode(200).extract().asString();
  }

  /** The page, then what it references, then what those load: every file the page is made of. */
  private static Set<String> files() {
    var seen = new LinkedHashSet<String>();
    var queue = new ArrayDeque<String>();
    queue.add("/admin/");
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

  /** The page's own files: its fonts and icons are the users' page's bundled ones. */
  private static List<String> ownFiles() {
    return files().stream().filter(file -> file.startsWith("/admin/")).toList();
  }

  @Test
  void thePageIsServed() {
    given()
        .get("/admin/")
        .then()
        .statusCode(200)
        .contentType(startsWith("text/html"))
        .body(containsString("<title>Admin - SignalHub</title>"))
        .body(containsString("<script type=\"module\" src=\"js/main.js\"></script>"));
  }

  @Test
  void everyFileThePageLoadsIsServed() {
    var files = files();
    assertTrue(
        files.containsAll(
            Set.of(
                "/admin/",
                "/admin/admin.css",
                "/admin/js/main.js",
                "/admin/js/devices.js",
                "/admin/js/producers.js",
                "/admin/js/status.js",
                "/admin/js/signin.js",
                "/admin/js/pairing.js",
                "/admin/js/events.js",
                "/admin/js/users.js",
                "/app/fonts/fonts.css",
                "/webjars/qrcode-generator/2.0.4/dist/qrcode.js")),
        files.toString());
    // The icon font and the typefaces come with the page's stylesheet, from the folder the users'
    // page bundles them in: nothing is fetched from anywhere else.
    assertTrue(files.stream().anyMatch(file -> file.endsWith(".woff2")));
    assertTrue(files.size() > 20, files.toString());
  }

  @Test
  void everyFileOfThePageHasTheStrictPolicyAndIsNeverFramedOrCached() {
    for (var path : ownFiles()) {
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
          .header("Cache-Control", equalTo("no-store"))
          .header("X-Content-Type-Options", equalTo("nosniff"));
    }
  }

  @Test
  void thePageHasNoInlineScriptStyleOrEventHandlerAndNamesNoOtherServer() {
    // The Content-Security-Policy would block them: every script and style is a file.
    for (var path : ownFiles()) {
      var text = given().get(path).then().extract().asString();
      if (path.endsWith("/") || path.endsWith(".html")) {
        assertFalse(Pattern.compile("<script(?![^>]*\\bsrc=)").matcher(text).find(), path);
        assertFalse(Pattern.compile("<style").matcher(text).find(), path);
        assertFalse(Pattern.compile("\\sstyle=").matcher(text).find(), path);
        assertFalse(Pattern.compile("\\son[a-z]+=").matcher(text).find(), path);
        assertFalse(Pattern.compile("\\s(?:src|href)=\"https?:").matcher(text).find(), path);
      }
      // No file names another server: the fonts, the icons and the QR encoder are bundled.
      assertFalse(
          Pattern.compile("https?://(?!www\\.w3\\.org)[a-z0-9.-]+\\.[a-z]{2,}")
              .matcher(text)
              .find(),
          path);
      if (path.endsWith(".js")) {
        assertFalse(text.contains("setAttribute(\"style\""), path);
        assertFalse(text.contains("eval("), path);
        assertFalse(text.contains("new Function"), path);
      }
    }
  }

  @Test
  void theAdminTokenAndProducerKeysAreNeverStoredAndNothingIsRenderedAsHtml() {
    for (var path : ownFiles()) {
      if (!path.endsWith(".js")) {
        continue;
      }
      var script = given().get(path).then().extract().asString();
      for (var forbidden :
          new String[] {
            "localStorage",
            "sessionStorage",
            "indexedDB",
            "document.cookie",
            "innerHTML",
            "outerHTML",
            "insertAdjacentHTML",
            "document.write",
            "history.pushState"
          }) {
        assertFalse(script.contains(forbidden), path + " uses " + forbidden);
      }
    }
    // The token lives in one module's closure, is checked before it is kept, and is forgotten by
    // signing out; it is sent only as a bearer header to this origin, never put in an address.
    var api = source("api.js");
    assertTrue(api.contains("let token = null;"));
    assertTrue(api.contains("token = candidate;"));
    assertTrue(
        Pattern.compile("export function forget\\(\\) \\{\\s*token = null;").matcher(api).find());
    assertTrue(api.contains("Authorization: `Bearer ${bearer}`"));
    // A new producer key is shown once, in a dialog, in the page's memory only.
    var producers = source("producers.js");
    assertTrue(producers.contains("showKey({ name: value, apiKey: issued.apiKey, fresh: true });"));
    assertTrue(producers.contains("Shown once. You won't see this key again."));
    assertTrue(producers.contains("Did you copy the key?"));
  }

  @Test
  void thePageHasTheRailTheStatusButtonAndTheAccountMenuAndKeepsItsSectionInTheAddress() {
    var page = page();
    for (var section : new String[] {"devices", "users", "producers", "events", "status"}) {
      assertTrue(
          Pattern.compile(
                  "<a class=\"ri\" href=\"#" + section + "\" data-section=\"" + section + "\">")
              .matcher(page)
              .find(),
          section);
    }
    assertTrue(page.contains("<nav id=\"rail\" class=\"rail\" aria-label=\"Sections\">"));
    assertTrue(
        page.contains("<nav id=\"bottom-bar\" class=\"nav\" aria-label=\"Sections (phone)\">"));
    assertTrue(
        page.contains(
            "id=\"status-button\" href=\"#status\" aria-label=\"Server status: checking\""));
    assertTrue(page.contains("id=\"account\" class=\"acct\" aria-label=\"Account\""));
    assertTrue(page.contains("<main id=\"main\" class=\"main\">"));
    // Events and Users are in the new shell with their earlier content.
    assertTrue(
        page.contains(
            "<div id=\"section-users\" class=\"legacy-section\" data-section=\"users\" hidden>"));
    assertTrue(
        page.contains(
            "<div id=\"section-events\" class=\"legacy-section\" data-section=\"events\" hidden>"));
    var router = source("router.js");
    assertTrue(
        router.contains(
            "export const SECTIONS = [\"devices\", \"users\", \"producers\", \"events\", \"status\"];"));
    // The address names the section, Devices when it names none; an id is checked against the
    // canonical form before it is used in a request path.
    assertTrue(router.contains("?? SECTIONS[0]"));
    assertTrue(
        router.contains(
            "export const ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;"));
    var main = source("main.js");
    assertTrue(main.contains("window.addEventListener(\"hashchange\""));
    // A 401 while signed in goes back to sign-in and keeps the address.
    assertTrue(main.contains("whenSessionLost("));
    assertTrue(main.contains("signInAgain(\"lost\")"));
    assertTrue(
        main.contains(
            "if (reason === \"signedOut\") keepAddress(location.pathname + location.search);"));
  }

  @Test
  void signingInChecksTheTokenWithTheManagementApiAndSaysWhatFailed() {
    var api = source("api.js");
    assertTrue(api.contains("export const CLIENTS = \"/api/v1/admin/clients\";"));
    assertTrue(api.contains("const response = await send(\"GET\", CLIENTS, null, candidate);"));
    assertTrue(
        api.contains(
            "if (response.status === 401) throw new ApiError(\"Wrong admin token\", \"wrong\", 401);"));
    assertTrue(api.contains("if (response.status === 404) throw new ApiError("));
    // A server that does not answer in 15 seconds is as good as one that cannot be reached.
    assertTrue(api.contains("const TIMEOUT_MS = 15_000;"));
    // A deletion answers 204 with no body.
    assertTrue(api.contains("response.status === 204 ? null : response.json()"));
    var signin = source("signin.js");
    assertTrue(signin.contains("const MIN_LENGTH = 32;"));
    assertTrue(signin.contains("autocomplete: \"current-password\""));
    assertTrue(signin.contains("\"Show the token\""));
    // Sign in stays off until the token has 32 characters.
    assertTrue(signin.contains("disabled: off || busy || typed.length < MIN_LENGTH,"));
  }

  @Test
  void theStatusIsReadFromWhatExistsAndTheManagementApiByOneRule() {
    var api = source("api.js");
    assertTrue(api.contains("export const STATUS = \"/api/v1/admin/status\";"));
    assertTrue(api.contains("export const INFO = \"/q/info\";"));
    assertTrue(api.contains("export const HEALTH = \"/q/health\";"));
    var signal = source("signal.js");
    // Every 30 seconds while the page is visible: the status and the health, and with Status open
    // the release, the devices and the newest event too, each part judged on its own.
    assertTrue(signal.contains("export const CHECK_MS = 30_000;"));
    assertTrue(signal.contains("if (document.visibilityState === \"visible\") check();"));
    assertTrue(
        Pattern.compile(
                "const requests = \\[settle\\(call\\(\"GET\", STATUS\\)\\), settle\\(probe\\(HEALTH\\)\\)\\];\\s*"
                    + "if \\(fullRead\\) \\{\\s*asked\\.push\\(\"info\", \"clients\", \"latest\"\\);\\s*"
                    + "requests\\.push\\(settle\\(probe\\(INFO\\)\\), settle\\(call\\(\"GET\", CLIENTS\\)\\), "
                    + "settle\\(call\\(\"GET\", `\\$\\{EVENTS\\}\\?limit=1`\\)\\)\\);")
            .matcher(signal)
            .find());
    // /q/ needs no token, so the page sends it none; health that is down answers 503 with its
    // checks, which the page still reads.
    var api2 = api;
    assertTrue(
        api2.contains(
            "response = await fetch(path, { cache: \"no-store\", signal: controller.signal });"));
    assertTrue(
        Pattern.compile(
                "try \\{\\s*return await response\\.json\\(\\);\\s*\\} catch \\{\\s*"
                    + "throw new ApiError\\(`SignalHub answered \\$\\{response\\.status\\}\\.`")
            .matcher(api2)
            .find());
    // A failure that is not one of SignalHub's own errors, such as a database that is down, is
    // said by its status, never shown as an empty error.
    assertTrue(
        api2.contains(
            "if (body.title) return details ? `${body.title}: ${details}` : body.title;"));
    assertTrue(api2.contains("return `SignalHub answered ${response.status}.`;"));
    // The rules of "needs attention" (docs/design/users/DESIGN.md, 9.5).
    var model = source("model.js");
    assertTrue(model.contains("export const WAITING_LIMIT = 20;"));
    assertTrue(model.contains("return now > WAITING_LIMIT && now >= before ? before : null;"));
    assertTrue(model.contains("given up since you opened this page"));
    assertTrue(
        model.contains(
            "status.value.abandonedRetries - (ctx.baseline ?? status.value.abandonedRetries)"));
    assertTrue(
        model.contains(
            "devices.withAddress.length > 0 && devices.failing.length === devices.withAddress.length"));
    assertTrue(model.contains("status.value.pushProviders"));
    assertTrue(model.contains("status.value.startedAt"));
    // A device counts while its latest result is a failure; a revoked one never does.
    assertTrue(
        Pattern.compile(
                "if \\(client\\.revokedAt \\|\\| !lastFailure\\) return false;\\s*"
                    + "return !lastSuccess \\|\\| Date\\.parse\\(lastFailure\\.at\\) >"
                    + " Date\\.parse\\(lastSuccess\\.at\\);")
            .matcher(model)
            .find());
    // Status only reads: it changes nothing.
    var status = source("status.js");
    assertFalse(Pattern.compile("call\\(\"(POST|PUT|PATCH|DELETE)\"").matcher(status).find());
    assertTrue(
        status.contains(
            "Nothing is changed on this page: settings are in the server's .env and take effect after a restart."));
  }

  @Test
  void theListsAreReadAgainEveryThirtySecondsAndNeverClearedByAFailedRead() {
    var list = source("list.js");
    assertTrue(list.contains("const REFRESH_MS = 30_000;"));
    assertTrue(
        list.contains(
            "if (document.visibilityState === \"visible\" && !document.querySelector(\".scrim\")) reload();"));
    // A failed read keeps the older list and says which: the banner and "Older list".
    assertTrue(list.contains("This is the list from ${clock(loadedAt)}."));
    assertTrue(list.contains("`Older list · ${clock(loadedAt)}`"));
    // The filters are kept in the address, as typed, and the pane is #section/<id>.
    assertTrue(list.contains("params.set(\"f\", filters.chip)"));
    assertTrue(list.contains("hashFor(cfg.name, id, query())"));
  }

  @Test
  void thePageManagesProducersWithTheManagementApiAndAsksBeforeWhatCannotBeUndone() {
    var api = source("api.js");
    assertTrue(api.contains("export const PRODUCERS = \"/api/v1/admin/producers\";"));
    var script = source("producers.js");
    // A producer is created for an owner, private or public, and its key shown once.
    assertTrue(
        script.contains(
            "issued = await call(\"POST\", PRODUCERS, { name: value, ownerId: owner.select.value,"
                + " visibility });"));
    assertTrue(script.contains("call(\"POST\", `${PRODUCERS}/${producer.id}/keys`)"));
    // Renaming goes through the admin API's update, and a taken name (409) is said on the field.
    assertTrue(script.contains("call(\"PATCH\", `${PRODUCERS}/${producer.id}`, { name })"));
    assertTrue(script.contains("error.status === 409"));
    // Revoking a key, disabling, making private and removing someone each ask first; enabling and
    // making public do not.
    for (var action :
        new String[] {
          "call(\"POST\", `${PRODUCERS}/${producer.id}/keys/${key.id}/revoke`)",
          "call(\"POST\", `${PRODUCERS}/${producer.id}/disable`)",
          "call(\"PATCH\", `${PRODUCERS}/${producer.id}`, { allowedUserIds: rest })"
        }) {
      assertTrue(script.contains(action), action);
    }
    assertTrue(
        Pattern.compile(
                "return confirmDialog\\(\\{\\s*title: `Disable \\$\\{producer\\.name\\}\\?`")
            .matcher(script)
            .find());
    assertTrue(script.contains("if (value === \"PUBLIC\") return run();"));
    assertTrue(script.contains("call(\"POST\", `${PRODUCERS}/${producer.id}/enable`)"));
    assertTrue(
        script.contains("call(\"PATCH\", `${PRODUCERS}/${producer.id}`, { visibility: value })"));
    // Who disabled it is the server's `disabledBy`.
    assertTrue(
        script.contains(
            "producer.disabledBy === \"OWNER\" ? \"Disabled by its owner\" : \"Disabled by the host\""));
    // A producer that went quiet stands out; a disabled one is not expected to publish.
    assertTrue(script.contains("const QUIET_DAYS = 7;"));
    assertTrue(
        Pattern.compile(
                "export function isQuiet\\(producer\\) \\{\\s*if \\(producer\\.disabledAt\\) return false;\\s*"
                    + "return !producer\\.lastEventAt \\|\\| Date\\.now\\(\\) - Date\\.parse\\(producer\\.lastEventAt\\) > QUIET_DAYS \\* DAY_MS;")
            .matcher(script)
            .find());
    // The key's label is built in the page: the server sends no prefix.
    assertTrue(script.contains("`shpk1_${key.id.replaceAll(\"-\", \"\").slice(0, 12)}…`"));
  }

  @Test
  void thePageManagesDevicesAndPairingCodesWithTheManagementApi() {
    var api = source("api.js");
    assertTrue(api.contains("export const PAIRINGS = \"/api/v1/admin/pairings\";"));
    var devices = source("devices.js");
    // Renaming, revoking and deleting go through the management API; Delete is offered only for a
    // revoked device, after a question; Revoke only for one that is not.
    assertTrue(devices.contains("call(\"PATCH\", `${CLIENTS}/${client.id}`, { name })"));
    assertTrue(devices.contains("call(\"POST\", `${CLIENTS}/${client.id}/revoke`)"));
    assertTrue(devices.contains("call(\"DELETE\", `${CLIENTS}/${client.id}`)"));
    assertTrue(
        Pattern.compile(
                "if \\(client\\.revokedAt\\) \\{\\s*body\\.push\\(\\s*el\\(\\s*\"div\",\\s*\\{ class: \"act\" \\},\\s*"
                    + "button\\(\"Delete\"")
            .matcher(devices)
            .find());
    // The open codes are listed and cancelled; a code is never listed (the server does not).
    assertTrue(devices.contains("call(\"GET\", PAIRINGS)"));
    assertTrue(devices.contains("call(\"DELETE\", `${PAIRINGS}/${code.id}`)"));
    var pairing = source("pairing.js");
    // The dialog makes the code for a named device of a chosen user, asks whether it was used every
    // 3 seconds while it is shown, and can cancel it.
    assertTrue(
        pairing.contains("call(\"POST\", PAIRINGS, { name: deviceName, userId: owner.id })"));
    assertTrue(pairing.contains("const POLL_MS = 3000;"));
    assertTrue(pairing.contains("call(\"GET\", `${PAIRINGS}/${pairing.id}`)"));
    assertTrue(pairing.contains("call(\"DELETE\", `${PAIRINGS}/${pairing.id}`)"));
    assertTrue(pairing.contains("answer.state !== \"REDEEMED\""));
    // The code is drawn as a QR on a white plate with black modules, in both themes.
    assertTrue(pairing.contains("context.fillStyle = \"#ffffff\";"));
    // No public address: the server answers the code without a link, and the dialog says so.
    assertTrue(pairing.contains("const noLink = !pairing.uri;"));
  }

  @Test
  void aChangeMadeOnThePageNeverOffersUndoAndAnythingThatCannotBeUndoneAsksFirst() {
    for (var path : new String[] {"producers.js", "devices.js", "pairing.js", "ui.js", "list.js"}) {
      var script = source(path);
      // The words of a button or a message: a comment may say there is none.
      assertFalse(Pattern.compile("[\"'`][^\"'`\\n]*Undo").matcher(script).find(), path);
      // The browser's own prompt and confirm cannot be styled or described: dialogs replace them.
      assertFalse(
          Pattern.compile("(?<![A-Za-z.])(confirm|prompt|alert)\\(").matcher(script).find(), path);
    }
    var ui = source("ui.js");
    // A dialog traps focus, starts on its first action (Cancel) and returns focus to what opened
    // it.
    assertTrue(ui.contains("document.addEventListener(\"keydown\", onKey, true);"));
    assertTrue(ui.contains("if (event.key === \"Escape\")"));
    assertTrue(ui.contains("target?.focus?.({ preventScroll: true });"));
    // A snack bar goes after 8 seconds or on Dismiss.
    assertTrue(ui.contains("const SNACK_MS = 8000;"));
  }

  @Test
  void theStylesheetKeepsEveryColourInATokenAndHasTheLightThemeAndReducedMotion() {
    var css = given().get("/admin/admin.css").then().statusCode(200).extract().asString();
    assertTrue(css.contains("@media (prefers-color-scheme: light)"));
    assertTrue(css.contains("@media (prefers-reduced-motion: reduce)"));
    assertTrue(css.contains("@media (max-width: 1179px)"));
    assertTrue(css.contains("@media (max-width: 599px)"));
    // Outside the two token sets and the QR plate, no rule writes a colour out.
    var tokens = css.indexOf("* {");
    var rules = css.substring(tokens);
    assertFalse(
        Pattern.compile("#[0-9a-fA-F]{3,8}\\b")
            .matcher(rules.replace("background: #ffffff;", ""))
            .find());
    assertFalse(Pattern.compile("rgba?\\(").matcher(rules).find());
    assertTrue(css.contains("outline: 2px solid var(--primary);"));
  }

  @Test
  void thePageManagesUsersWithTheManagementApiAndAsksBeforeWhatCannotBeUndone() {
    var script = given().get("/admin/js/users.js").then().statusCode(200).extract().asString();
    assertTrue(source("api.js").contains("export const USERS = \"/api/v1/admin/users\";"));
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
    // A device is connected to a user, in the Devices section's dialog with the user chosen.
    assertTrue(script.contains("openConnect({ user });"));
    assertTrue(
        source("pairing.js")
            .contains("call(\"POST\", PAIRINGS, { name: deviceName, userId: owner.id })"));
    assertFalse(source("pairing.js").contains("admin: "));
    // The role is only ever changed from this page, through the admin token.
    var page = given().get("/admin/").then().extract().asString();
    assertTrue(page.contains("Making someone an admin"));
    assertTrue(page.contains("id=\"invite-role\""));
  }

  @Test
  void aUserShowsItsTrafficWhenAskedForAsTextWithLinksToItsEvents() {
    var script = given().get("/admin/js/users.js").then().statusCode(200).extract().asString();
    // Read only when opened, with the admin token like every other request.
    assertTrue(script.contains("await call(\"GET\", `${USERS}/${user.id}/traffic`)"));
    assertTrue(script.contains("item.append(trafficOf(user));"));
    // An event is linked by its ID in the page's own address, a title and a name set as text.
    assertTrue(script.contains("link.href = `#events/${e.id}`;"));
    assertTrue(script.contains("link.href = `#events/${d.eventId}`;"));
    assertTrue(script.contains("const link = element(\"a\", null, e.title);"));
    assertTrue(script.contains("element(\"strong\", null, d.clientName)"));
    assertFalse(script.contains("innerHTML"));
  }

  @Test
  void thePageBrowsesEventsWithTheListingAPageAtATime() {
    var script = given().get("/admin/js/events.js").then().statusCode(200).extract().asString();
    assertTrue(source("api.js").contains("export const EVENTS = \"/api/v1/events\";"));
    // The app inbox's filters, each only when chosen, and the page's cursor.
    for (var filter :
        new String[] {
          "producerId: \"filter-producer\"",
          "category: \"filter-category\"",
          "severity: \"filter-severity\"",
          "userId: \"filter-user\"",
          "relation: \"filter-relation\"",
          "read: \"filter-read\""
        }) {
      assertTrue(script.contains(filter), filter);
    }
    // The user's producers are asked for only with a user: the server refuses one without.
    assertTrue(
        script.contains("if ($(id).value && !$(id).disabled) query.set(name, $(id).value);"));
    assertTrue(script.contains("$(\"filter-relation\").disabled = !$(\"filter-user\").value;"));
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
    var script = given().get("/admin/js/events.js").then().statusCode(200).extract().asString();
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
    var script = given().get("/admin/js/events.js").then().statusCode(200).extract().asString();
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
  void anEventGroupsItsDeliveriesByTheUsersItReachedAndTheEventsFilterByUser() {
    var script = given().get("/admin/js/events.js").then().statusCode(200).extract().asString();
    // A user per entry, named as text, with a badge for the owner; a device-less user says so.
    assertTrue(script.contains("const title = element(\"strong\", null, user.name);"));
    assertTrue(
        script.contains(
            "if (user.owner) item.append(\" \", element(\"span\", \"badge muted\", \"Owner\"));"));
    assertTrue(script.contains("const byUser = new Map(reached.map("));
    var page = given().get("/admin/").then().extract().asString();
    for (var control :
        new String[] {
          "<select id=\"filter-user\">",
          "<select id=\"filter-relation\" disabled>",
          "<option value=\"OWNED\">Owned</option>",
          "<option value=\"SUBSCRIBED\">Subscribed to</option>"
        }) {
      assertTrue(page.contains(control), control);
    }
  }

  @Test
  void anEventShowsItsDeliveriesOneLinePerDeviceAsText() {
    var script = given().get("/admin/js/events.js").then().statusCode(200).extract().asString();
    // Read with the admin token once the event is shown, and again on Refresh.
    assertTrue(
        script.contains(
            "renderDeliveries(await call(\"GET\", `${ADMIN_EVENTS}/${eventId}/deliveries`));"));
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
        script.contains("if (!devices.has(record.clientId)) devices.set(record.clientId, []);"));
    assertTrue(script.contains("element(\"strong\", null, last.clientName),"));
    assertTrue(script.contains("`: ${outcome(last)}, ${time(last.at)} (${ago(last.at)})`,"));
    assertTrue(
        source("legacy.js")
            .contains("return record.detail ? `${text} (${record.detail})` : text;"));
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
    var script = given().get("/admin/js/events.js").then().statusCode(200).extract().asString();
    assertTrue(source("api.js").contains("export const ADMIN_EVENTS = \"/api/v1/admin/events\";"));
    assertTrue(
        source("api.js").contains("export const DELETE_EVENTS = \"/api/v1/admin/events/delete\";"));
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
    assertTrue(script.contains("deleteEvents(\n    { ids },"));
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
    var script = given().get("/admin/js/events.js").then().statusCode(200).extract().asString();
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

  @ParameterizedTest
  @ValueSource(strings = {"/connect", "/connect/", "/connect/connect.js"})
  void theConnectPageOfEarlierReleasesIsGone(String path) {
    given().redirects().follow(false).get(path).then().statusCode(404);
  }

  @Test
  void theOldSingleScriptIsGone() {
    given().get("/admin/admin.js").then().statusCode(404);
  }
}
