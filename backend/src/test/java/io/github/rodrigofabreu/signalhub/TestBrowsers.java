package io.github.rodrigofabreu.signalhub;

import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.restassured.RestAssured.given;

import io.github.rodrigofabreu.signalhub.TestClients.Registered;
import io.restassured.http.ContentType;
import io.restassured.specification.RequestSpecification;

/** Signs browsers in the way the page and the app do. */
public final class TestBrowsers {

  public static final String WEB = "/api/v1/web";
  public static final String SIGN_INS = "/api/v1/client/web-sign-ins";
  public static final String COOKIE = "__Host-signalhub_session";
  public static final String FIREFOX_ON_LINUX =
      "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0";

  private TestBrowsers() {}

  /** A page that has started a sign-in, with what it shows and holds. */
  public record Page(String id, String pollSecret, String code, String scanCode) {

    public RequestSpecification poll() {
      return given().header("Authorization", "Bearer " + pollSecret);
    }
  }

  /** A signed-in browser: its session cookie value and its CSRF token. */
  public record Browser(String id, String sessionKey, String csrf) {

    /** A request from the page: the cookie alone, as a safe request needs. */
    public RequestSpecification get() {
      return given().header("Cookie", COOKIE + "=" + sessionKey);
    }

    /** A state-changing request from the page: the cookie and the token. */
    public RequestSpecification change() {
      return get().header("X-SignalHub-CSRF", csrf).contentType(ContentType.JSON);
    }
  }

  public static Page start(String userAgent) {
    var started =
        given()
            .header("User-Agent", userAgent)
            .when()
            .post(WEB + "/sign-ins")
            .then()
            .statusCode(201)
            .extract();
    return new Page(
        started.path("id"),
        started.path("pollSecret"),
        started.path("code"),
        started.path("scanCode"));
  }

  /** The device looks the code up and approves; the page is not polled yet. */
  public static void approve(Registered device, Page page) {
    var id =
        asClient(device.clientKey())
            .contentType(ContentType.JSON)
            .body("{\"code\": \"" + page.code() + "\"}")
            .when()
            .post(SIGN_INS + "/lookup")
            .then()
            .statusCode(200)
            .extract()
            .path("id");
    asClient(device.clientKey())
        .when()
        .post(SIGN_INS + "/" + id + "/approve")
        .then()
        .statusCode(204);
  }

  /** The whole sign-in: start, approve from the device, poll. */
  public static Browser signIn(Registered device, String userAgent) {
    var page = start(userAgent);
    approve(device, page);
    var polled = page.poll().when().get(WEB + "/sign-ins/" + page.id()).then().statusCode(200);
    var cookie = polled.extract().header("Set-Cookie");
    var key = cookie.substring(COOKIE.length() + 1, cookie.indexOf(';'));
    var session = given().header("Cookie", COOKIE + "=" + key).get(WEB + "/session");
    return new Browser(session.path("client.id"), key, session.path("csrfToken"));
  }

  public static Browser signIn(Registered device) {
    return signIn(device, FIREFOX_ON_LINUX);
  }
}
