package io.github.rodrigofabreu.signalhub.client;

import static io.github.rodrigofabreu.signalhub.TestBrowsers.COOKIE;
import static io.github.rodrigofabreu.signalhub.TestBrowsers.FIREFOX_ON_LINUX;
import static io.github.rodrigofabreu.signalhub.TestBrowsers.SIGN_INS;
import static io.github.rodrigofabreu.signalhub.TestBrowsers.WEB;
import static io.github.rodrigofabreu.signalhub.TestClients.CLIENT;
import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.matchesPattern;
import static org.hamcrest.Matchers.not;
import static org.hamcrest.Matchers.notNullValue;
import static org.hamcrest.Matchers.nullValue;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.agroal.api.AgroalDataSource;
import io.github.rodrigofabreu.signalhub.TestBrowsers;
import io.github.rodrigofabreu.signalhub.TestClients;
import io.github.rodrigofabreu.signalhub.push.DeviceNotifier;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import jakarta.inject.Inject;
import java.sql.SQLException;
import java.time.Duration;
import java.time.Instant;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/**
 * Signing a browser in from a device, against real PostgreSQL: the session cookie, the CSRF rules,
 * what each role may do with browsers, a revoked browser signed out, and the bounds on wrong codes.
 */
@QuarkusTest
class WebSignInApiTest {

  @Inject AgroalDataSource dataSource;
  @Inject DeviceNotifier notifier;

  // Each sign-in pushes a notice to the clients other tests gave push targets; it must be sent
  // before those tests count their pushes.
  @AfterEach
  void awaitNotices() throws Exception {
    notifier.awaitSent(Duration.ofSeconds(10));
  }

  @Test
  void aPageStartsASignInWithItsCodes() {
    given()
        .header("User-Agent", FIREFOX_ON_LINUX)
        .when()
        .post(WEB + "/sign-ins")
        .then()
        .statusCode(201)
        .header("Cache-Control", "no-store")
        .body("id", notNullValue())
        .body("code", matchesPattern("[A-HJKMNP-Z2-9]{3}-[A-HJKMNP-Z2-9]{3}"))
        .body("scanCode", matchesPattern("shsc1_[A-Za-z0-9_-]{22}"))
        .body("pollSecret", matchesPattern("shsp1_[A-Za-z0-9_-]{43}"))
        .body("uri", matchesPattern("signalhub://signin\\?server=https%3A%2F%2F.*&code=shsc1_.*"))
        .body("browserName", equalTo("Firefox on Linux"));
  }

  @Test
  void aDeviceSignsABrowserInAndThePageGetsAnHttpOnlyStrictCookie() {
    var device = TestClients.registerAs("BASIC", "signin-phone");
    var page = TestBrowsers.start(FIREFOX_ON_LINUX);

    page.poll().when().get(WEB + "/sign-ins/" + page.id()).then().body("state", equalTo("PENDING"));

    var asked =
        asClient(device.clientKey())
            .contentType(ContentType.JSON)
            // A person types it in any case, with or without the dash.
            .body("{\"code\": \"" + page.code().toLowerCase().replace("-", " ") + "\"}")
            .when()
            .post(SIGN_INS + "/lookup")
            .then()
            .statusCode(200)
            .body("id", equalTo(page.id()))
            .body("browserName", equalTo("Firefox on Linux"));
    page.poll().when().get(WEB + "/sign-ins/" + page.id()).then().body("state", equalTo("ASKED"));

    asClient(device.clientKey())
        .when()
        .post(SIGN_INS + "/" + asked.extract().path("id") + "/approve")
        .then()
        .statusCode(204);

    var signedIn =
        page.poll()
            .when()
            .get(WEB + "/sign-ins/" + page.id())
            .then()
            .statusCode(200)
            .body("state", equalTo("SIGNED_IN"))
            .extract();
    var cookie = signedIn.header("Set-Cookie");
    assertTrue(cookie.startsWith(COOKIE + "=shck1_"), cookie);
    assertTrue(cookie.contains("; HttpOnly"), cookie);
    assertTrue(cookie.contains("; Secure"), cookie);
    assertTrue(cookie.contains("SameSite=Strict"), cookie);
    assertTrue(cookie.contains("Path=/"), cookie);
    assertTrue(cookie.contains("Max-Age=2592000"), cookie);
    assertTrue(!cookie.contains("Domain"), cookie);

    // The session is collected once: the same page learns nothing more, and gets no second cookie.
    page.poll()
        .when()
        .get(WEB + "/sign-ins/" + page.id())
        .then()
        .body("state", equalTo("EXPIRED"))
        .header("Set-Cookie", nullValue());
  }

  @Test
  void theBrowserIsAClientOfTheApprovingUsersListedAsABrowserForThirtyDays() throws SQLException {
    var device = TestClients.registerAs("MOD", "listed-phone");
    var browser = TestBrowsers.signIn(device);

    var session = browser.get().when().get(WEB + "/session").then().statusCode(200).extract();
    assertEquals("BROWSER", session.path("client.kind"));
    assertEquals("Firefox on Linux", session.path("client.name"));
    assertEquals(device.userId().toString(), session.path("client.user.id"));
    var expires = Instant.parse(session.path("client.expiresAt"));
    var days = Duration.between(Instant.now(), expires).toHours();
    assertTrue(days >= 30 * 24 - 1 && days <= 30 * 24, "expires in " + days + " hours");

    // Listed with the user's devices, as a browser.
    asClient(device.clientKey())
        .when()
        .get(CLIENT + "/devices")
        .then()
        .body("items.findAll { it.kind == 'BROWSER' }.id", hasItem(browser.id()))
        .body("items.findAll { it.id == '" + device.id() + "' }.kind", hasItem("DEVICE"));

    // Only hashes are stored: neither the key nor the codes appear in the table.
    try (var connection = dataSource.getConnection();
        var statement =
            connection.prepareStatement(
                "SELECT count(*) FROM clients WHERE encode(key_hash, 'escape') LIKE 'shck1_%'")) {
      var rows = statement.executeQuery();
      rows.next();
      assertEquals(0, rows.getInt(1));
    }
  }

  @Test
  void theBrowserReadsTheClientApiWithItsCookieAndHasThePermissionsOfItsUser() {
    var device = TestClients.registerAs("BASIC", "reads-phone");
    var browser = TestBrowsers.signIn(device);

    browser
        .get()
        .when()
        .get(CLIENT)
        .then()
        .statusCode(200)
        .body("id", equalTo(browser.id()))
        .body("user.role", equalTo("BASIC"));
    browser.get().when().get("/api/v1/events").then().statusCode(200);
    // A basic user's browser cannot pair a device, as their device cannot.
    browser
        .change()
        .body("{\"name\": \"Tablet\"}")
        .when()
        .post(CLIENT + "/pairings")
        .then()
        .statusCode(403);
  }

  @Test
  void theSessionDoesNotWorkWithoutItsCookieOrWithAnotherCredentialInIt() {
    var device = TestClients.registerAs("MOD", "cookie-phone");
    var browser = TestBrowsers.signIn(device);

    given().when().get(WEB + "/session").then().statusCode(401);
    given()
        .header("Cookie", COOKIE + "=garbage")
        .when()
        .get(WEB + "/session")
        .then()
        .statusCode(401);
    // A device's key is not a session: the cookie is for browsers only.
    given()
        .header("Cookie", COOKIE + "=" + device.clientKey())
        .when()
        .get(CLIENT)
        .then()
        .statusCode(401);
    // The admin token never works as a cookie, so the admin page's token stays host only.
    given()
        .header("Cookie", COOKIE + "=test-only-admin-token-0123456789abcdef")
        .when()
        .get("/api/v1/admin/clients")
        .then()
        .statusCode(401);
    // A bearer key wins when both are sent: a wrong one is not rescued by a good cookie.
    given()
        .header("Cookie", COOKIE + "=" + browser.sessionKey())
        .header("Authorization", "Bearer wrong")
        .when()
        .get(CLIENT)
        .then()
        .statusCode(401);
    // The session endpoint answers only to a cookie.
    asClient(device.clientKey()).when().get(WEB + "/session").then().statusCode(401);
  }

  @Test
  void aStateChangingRequestNeedsTheCsrfTokenAndASameHostOrigin() {
    var device = TestClients.registerAs("MOD", "csrf-phone");
    var browser = TestBrowsers.signIn(device);
    var url = CLIENT + "/devices/" + browser.id();
    var rename = "{\"name\": \"Work laptop\"}";

    // The cookie alone is not enough, however it got there.
    browser
        .get()
        .contentType(ContentType.JSON)
        .body(rename)
        .when()
        .patch(url)
        .then()
        .statusCode(403);
    browser
        .get()
        .header("X-SignalHub-CSRF", "wrong")
        .contentType(ContentType.JSON)
        .body(rename)
        .when()
        .patch(url)
        .then()
        .statusCode(403);
    // The token of another session is no better.
    var other = TestBrowsers.signIn(device);
    browser
        .get()
        .header("X-SignalHub-CSRF", other.csrf())
        .contentType(ContentType.JSON)
        .body(rename)
        .when()
        .patch(url)
        .then()
        .statusCode(403);
    // A request from another origin is refused even with the token.
    browser
        .change()
        .header("Origin", "https://evil.example")
        .body(rename)
        .when()
        .patch(url)
        .then()
        .statusCode(403);
    browser.change().header("Origin", "null").body(rename).when().patch(url).then().statusCode(403);
    // The page's own origin is accepted.
    browser
        .change()
        .header("Origin", "http://localhost:8081")
        .header("Host", "localhost:8081")
        .body(rename)
        .when()
        .patch(url)
        .then()
        .statusCode(200)
        .body("name", equalTo("Work laptop"));
    browser.change().body("{\"name\": \"Laptop\"}").when().patch(url).then().statusCode(200);
    // Reading needs no token.
    browser.get().when().get(CLIENT).then().statusCode(200);
    // A bearer key needs none: no cookie, nothing to forge.
    asClient(device.clientKey())
        .contentType(ContentType.JSON)
        .body("{\"name\": \"Laptop 2\"}")
        .when()
        .patch(url)
        .then()
        .statusCode(200);
  }

  @Test
  void signingOutRevokesTheBrowserAndClearsTheCookie() {
    var device = TestClients.registerAs("BASIC", "signout-phone");
    var browser = TestBrowsers.signIn(device);
    var other = TestBrowsers.signIn(device);

    browser.get().when().post(WEB + "/session/sign-out").then().statusCode(403);
    var response =
        browser.change().when().post(WEB + "/session/sign-out").then().statusCode(204).extract();
    var cookie = response.header("Set-Cookie");
    assertTrue(cookie.startsWith(COOKIE + "=;"), cookie);
    assertTrue(cookie.contains("Max-Age=0"), cookie);

    browser.get().when().get(WEB + "/session").then().statusCode(401);
    // Only this browser: the device and the other browser stay signed in.
    asClient(device.clientKey()).when().get(CLIENT).then().statusCode(200);
    other.get().when().get(WEB + "/session").then().statusCode(200);
  }

  @Test
  void revokingABrowserFromADeviceSignsItOut() {
    var device = TestClients.registerAs("MOD", "revoker-phone");
    var second = TestClients.registerFor(device.userId(), "revoker-second");
    var browser = TestBrowsers.signIn(device);

    asClient(device.clientKey())
        .when()
        .post(CLIENT + "/devices/" + browser.id() + "/revoke")
        .then()
        .statusCode(200)
        .body("revokedAt", notNullValue());
    browser.get().when().get(WEB + "/session").then().statusCode(401);
    browser.get().when().get("/api/v1/events").then().statusCode(401);

    // The operator can too, and a revoked user's browsers go with them.
    var third = TestBrowsers.signIn(second);
    asAdmin().when().post("/api/v1/admin/clients/" + third.id() + "/revoke").then().statusCode(200);
    third.get().when().get(WEB + "/session").then().statusCode(401);
    var fourth = TestBrowsers.signIn(second);
    asAdmin()
        .when()
        .post("/api/v1/admin/users/" + device.userId() + "/revoke")
        .then()
        .statusCode(200);
    fourth.get().when().get(WEB + "/session").then().statusCode(401);
  }

  @Test
  void aSessionEndsAfterItsThirtyDays() throws SQLException {
    var device = TestClients.registerAs("BASIC", "expiry-phone");
    var browser = TestBrowsers.signIn(device);
    browser.get().when().get(WEB + "/session").then().statusCode(200);

    try (var connection = dataSource.getConnection();
        var statement =
            connection.prepareStatement(
                "UPDATE clients SET expires_at = now() - interval '1 second' WHERE id = ?::uuid")) {
      statement.setString(1, browser.id());
      statement.executeUpdate();
    }

    browser.get().when().get(WEB + "/session").then().statusCode(401);
  }

  @Test
  void everyRoleMayApproveASignInAndOnlyForItsOwnUser() {
    for (var role : new String[] {"BASIC", "MOD", "ADMIN"}) {
      var device = TestClients.registerAs(role, "approver-" + role.toLowerCase());
      var browser = TestBrowsers.signIn(device);
      browser
          .get()
          .when()
          .get(CLIENT)
          .then()
          .body("user.id", equalTo(device.userId().toString()))
          .body("user.role", equalTo(role));
    }
  }

  @Test
  void aBrowserCannotSignAnotherBrowserIn() {
    var device = TestClients.registerAs("ADMIN", "mint-phone");
    var browser = TestBrowsers.signIn(device);
    var page = TestBrowsers.start(FIREFOX_ON_LINUX);

    browser
        .change()
        .body("{\"code\": \"" + page.code() + "\"}")
        .when()
        .post(SIGN_INS + "/lookup")
        .then()
        .statusCode(403);
  }

  @Test
  void onlyTheDeviceThatLookedTheCodeUpMayApproveOrCancel() {
    var device = TestClients.registerAs("MOD", "asker-phone");
    var stranger = TestClients.registerAs("MOD", "stranger-phone");
    var page = TestBrowsers.start(FIREFOX_ON_LINUX);

    // Approving needs a lookup first, so knowing the page's ID is not enough.
    asClient(stranger.clientKey())
        .when()
        .post(SIGN_INS + "/" + page.id() + "/approve")
        .then()
        .statusCode(404);
    asClient(device.clientKey())
        .contentType(ContentType.JSON)
        .body("{\"code\": \"" + page.scanCode() + "\"}")
        .when()
        .post(SIGN_INS + "/lookup")
        .then()
        .statusCode(200);
    asClient(stranger.clientKey())
        .when()
        .post(SIGN_INS + "/" + page.id() + "/approve")
        .then()
        .statusCode(404);
    asClient(stranger.clientKey())
        .when()
        .post(SIGN_INS + "/" + page.id() + "/cancel")
        .then()
        .statusCode(404);
    page.poll().when().get(WEB + "/sign-ins/" + page.id()).then().body("state", equalTo("ASKED"));
  }

  @Test
  void cancellingTellsThePage() {
    var device = TestClients.registerAs("BASIC", "cancel-phone");
    var page = TestBrowsers.start(FIREFOX_ON_LINUX);
    asClient(device.clientKey())
        .contentType(ContentType.JSON)
        .body("{\"code\": \"" + page.code() + "\"}")
        .when()
        .post(SIGN_INS + "/lookup")
        .then()
        .statusCode(200);

    asClient(device.clientKey())
        .when()
        .post(SIGN_INS + "/" + page.id() + "/cancel")
        .then()
        .statusCode(204);

    page.poll()
        .when()
        .get(WEB + "/sign-ins/" + page.id())
        .then()
        .body("state", equalTo("CANCELLED"))
        .header("Set-Cookie", nullValue());
    // A cancelled sign-in cannot be approved afterwards.
    asClient(device.clientKey())
        .when()
        .post(SIGN_INS + "/" + page.id() + "/approve")
        .then()
        .statusCode(404);
  }

  @Test
  void theCodesExpire() throws SQLException {
    var device = TestClients.registerAs("BASIC", "expire-phone");
    var page = TestBrowsers.start(FIREFOX_ON_LINUX);
    expire(page.id());

    page.poll().when().get(WEB + "/sign-ins/" + page.id()).then().body("state", equalTo("EXPIRED"));
    asClient(device.clientKey())
        .contentType(ContentType.JSON)
        .body("{\"code\": \"" + page.code() + "\"}")
        .when()
        .post(SIGN_INS + "/lookup")
        .then()
        .statusCode(404);
  }

  @Test
  void anApprovedSignInNotCollectedInTimeGivesNoSession() throws SQLException {
    var device = TestClients.registerAs("BASIC", "late-phone");
    var page = TestBrowsers.start(FIREFOX_ON_LINUX);
    TestBrowsers.approve(device, page);
    expire(page.id());

    page.poll()
        .when()
        .get(WEB + "/sign-ins/" + page.id())
        .then()
        .body("state", equalTo("EXPIRED"))
        .header("Set-Cookie", nullValue());
  }

  @Test
  void pollingNeedsTheSecretThePageWasGiven() {
    var page = TestBrowsers.start(FIREFOX_ON_LINUX);
    var other = TestBrowsers.start(FIREFOX_ON_LINUX);

    given().when().get(WEB + "/sign-ins/" + page.id()).then().statusCode(401);
    // Neither the codes it shows nor another page's secret poll it.
    given()
        .header("Authorization", "Bearer " + page.scanCode())
        .when()
        .get(WEB + "/sign-ins/" + page.id())
        .then()
        .statusCode(401);
    other.poll().when().get(WEB + "/sign-ins/" + page.id()).then().statusCode(401);
    given()
        .header("Authorization", "Bearer " + other.pollSecret())
        .when()
        .get(WEB + "/sign-ins/00000000-0000-7000-8000-000000000000")
        .then()
        .statusCode(401);
  }

  @Test
  void aDeviceWithTooManyWrongCodesIsRefusedEvenForTheRightOne() {
    var device = TestClients.registerAs("BASIC", "guess-phone");
    var page = TestBrowsers.start(FIREFOX_ON_LINUX);

    for (var i = 0; i < WebSignInService.MAX_WRONG_PER_DEVICE; i++) {
      lookup(device, "ZZZ-ZZ" + (i + 2)).statusCode(404);
    }
    lookup(device, "ZZZ-ZZ9").statusCode(429);
    lookup(device, page.code()).statusCode(429);

    // Another device is not held back by it, and the page is still there.
    var other = TestClients.registerAs("BASIC", "guess-other");
    lookup(other, page.code()).statusCode(200);
  }

  @Test
  void aSignInForAUserRevokedBeforeItIsCollectedGivesNoSession() {
    var device = TestClients.registerAs("BASIC", "gone-phone");
    var page = TestBrowsers.start(FIREFOX_ON_LINUX);
    TestBrowsers.approve(device, page);
    asAdmin()
        .when()
        .post("/api/v1/admin/users/" + device.userId() + "/revoke")
        .then()
        .statusCode(200);

    page.poll()
        .when()
        .get(WEB + "/sign-ins/" + page.id())
        .then()
        .body("state", equalTo("CANCELLED"))
        .header("Set-Cookie", nullValue());
  }

  @ParameterizedTest
  @ValueSource(strings = {"BASIC", "MOD", "ADMIN"})
  void everyRoleSignsOutItsOwnBrowserFromTheDevicesList(String role) {
    var device = TestClients.registerAs(role, "list-" + role.toLowerCase());
    var browser = TestBrowsers.signIn(device);

    asClient(device.clientKey())
        .contentType(ContentType.JSON)
        .body("{\"name\": \"Home PC\"}")
        .when()
        .patch(CLIENT + "/devices/" + browser.id())
        .then()
        .statusCode(200)
        .body("name", equalTo("Home PC"));
    asClient(device.clientKey())
        .when()
        .post(CLIENT + "/devices/" + browser.id() + "/revoke")
        .then()
        .statusCode(200);
    asClient(device.clientKey())
        .when()
        .delete(CLIENT + "/devices/" + browser.id())
        .then()
        .statusCode(204);
  }

  @Test
  void aBasicUserStillCannotChangeAnyDeviceOrAnotherUsersBrowser() {
    var basic = TestClients.registerAs("BASIC", "basic-limits");
    var sibling = TestClients.registerFor(basic.userId(), "basic-limits-tablet");
    var someoneElse = TestClients.registerAs("MOD", "basic-limits-mod");
    var theirBrowser = TestBrowsers.signIn(someoneElse);
    var ownBrowser = TestBrowsers.signIn(basic);

    for (var target :
        new String[] {
          sibling.id().toString(),
          someoneElse.id().toString(),
          theirBrowser.id(),
          "00000000-0000-7000-8000-000000000000"
        }) {
      asClient(basic.clientKey())
          .when()
          .post(CLIENT + "/devices/" + target + "/revoke")
          .then()
          .statusCode(403)
          .body("title", equalTo("Not allowed for your role"));
    }
    // The browser too is refused: its user is basic, so it is the same rule.
    ownBrowser
        .change()
        .when()
        .post(CLIENT + "/devices/" + sibling.id() + "/revoke")
        .then()
        .statusCode(403);
    ownBrowser
        .change()
        .when()
        .post(CLIENT + "/devices/" + theirBrowser.id() + "/revoke")
        .then()
        .statusCode(403);
    // And it may sign itself out through the list.
    ownBrowser
        .change()
        .when()
        .post(CLIENT + "/devices/" + ownBrowser.id() + "/revoke")
        .then()
        .statusCode(200);
  }

  @Test
  void aModMayNotRevokeTheirOnlyDeviceBecauseABrowserRemains() {
    var mod = TestClients.registerAs("MOD", "last-mod");
    var browser = TestBrowsers.signIn(mod);

    // The browser does not count: a mod left with one cannot approve a sign-in or pair a device.
    browser
        .change()
        .when()
        .post(CLIENT + "/devices/" + mod.id() + "/revoke")
        .then()
        .statusCode(409)
        .body("title", equalTo("Cannot revoke the last active device of a user"));
  }

  @Test
  void anAdminCannotChangeAnotherAdminsBrowserFromADevice() {
    var admin = TestClients.registerAs("ADMIN", "admin-one");
    var other = TestClients.registerAs("ADMIN", "admin-two");
    var theirBrowser = TestBrowsers.signIn(other);

    asClient(admin.clientKey())
        .when()
        .post(CLIENT + "/devices/" + theirBrowser.id() + "/revoke")
        .then()
        .statusCode(409)
        .body("title", containsString("admin device"));
  }

  @Test
  void aPageLoadsNoDeviceKeyAndTheAdminPageStaysOffTheClientApi() {
    // The proxy forwards /api/ and the page, never /admin/ or the management API.
    given().when().get("/api/v1/admin/clients").then().statusCode(401);
    given().when().get(WEB + "/sign-ins").then().statusCode(not(equalTo(200)));
  }

  private io.restassured.response.ValidatableResponse lookup(
      TestClients.Registered device, String code) {
    return asClient(device.clientKey())
        .contentType(ContentType.JSON)
        .body("{\"code\": \"" + code + "\"}")
        .when()
        .post(SIGN_INS + "/lookup")
        .then();
  }

  private void expire(String id) throws SQLException {
    try (var connection = dataSource.getConnection();
        var statement =
            connection.prepareStatement(
                "UPDATE web_sign_ins SET expires_at = now() - interval '1 second'"
                    + " WHERE id = ?::uuid")) {
      statement.setString(1, id);
      statement.executeUpdate();
    }
  }
}
