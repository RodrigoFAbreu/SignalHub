package io.github.rodrigofabreu.signalhub.client;

import io.github.rodrigofabreu.signalhub.api.ApiError;
import io.github.rodrigofabreu.signalhub.producer.BearerToken;
import jakarta.enterprise.event.Event;
import jakarta.ws.rs.ClientErrorException;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.HeaderParam;
import jakarta.ws.rs.NotAuthorizedException;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.HttpHeaders;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.enums.SecuritySchemeIn;
import org.eclipse.microprofile.openapi.annotations.enums.SecuritySchemeType;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.parameters.Parameter;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import org.eclipse.microprofile.openapi.annotations.security.SecurityRequirement;
import org.eclipse.microprofile.openapi.annotations.security.SecurityScheme;
import org.eclipse.microprofile.openapi.annotations.tags.Tag;

/**
 * What the users' web page calls to sign a browser in and out: it starts a sign-in, polls it, and
 * with its session cookie reads its own session and signs out. Under {@code /api/v1}, so the proxy
 * forwards it like the rest of the client API. Everything else the page does is the client API,
 * authenticated by the same cookie.
 */
@Path("/api/v1/web")
@Tag(name = "Web sign-in")
@SecurityScheme(
    securitySchemeName = WebSignInResource.SESSION_SCHEME,
    type = SecuritySchemeType.APIKEY,
    in = SecuritySchemeIn.COOKIE,
    apiKeyName = WebSession.COOKIE,
    description =
        "A signed-in browser's session: an HttpOnly, Secure, SameSite=Strict cookie that holds the"
            + " browser's client key and lasts a fixed 30 days. It authenticates the client API"
            + " too; a state-changing request with it must also send the X-SignalHub-CSRF header"
            + " (GET /api/v1/web/session gives its value) and, if it has an Origin, the"
            + " server's own.")
@SecurityScheme(
    securitySchemeName = WebSignInResource.POLL_SCHEME,
    type = SecuritySchemeType.HTTP,
    scheme = "bearer",
    bearerFormat = "shsp1_<secret>",
    description = "The secret the page was given when it started a sign-in, to poll it.")
@Produces(MediaType.APPLICATION_JSON)
public class WebSignInResource {

  public static final String SESSION_SCHEME = "webSession";
  public static final String POLL_SCHEME = "webSignInPoll";

  private final WebSignInService signIns;
  private final ClientService clients;
  private final AuthenticatedClient caller;
  private final Event<BrowserSignedIn> signedIn;

  WebSignInResource(
      WebSignInService signIns,
      ClientService clients,
      AuthenticatedClient caller,
      Event<BrowserSignedIn> signedIn) {
    this.signIns = signIns;
    this.clients = clients;
    this.caller = caller;
    this.signedIn = signedIn;
  }

  @Schema(name = "WebSignIn", description = "A sign-in a page has started. Shown only here.")
  public record Started(
      @Schema(required = true, description = "The sign-in's ID, to poll it.") UUID id,
      @Schema(
              required = true,
              description =
                  "The page's own secret, to poll with as `Authorization: Bearer <pollSecret>`."
                      + " It is never shown on screen.",
              examples = "shsp1_EXAMPLE-not-a-secret-000000000000000000000")
          String pollSecret,
      @Schema(
              required = true,
              description = "The short code a person types in the app, as shown.",
              examples = "K7Q-4MX")
          String code,
      @Schema(
              required = true,
              description = "The longer code that goes in the QR code and the link.",
              examples = "shsc1_EXAMPLE-not-a-code0000")
          String scanCode,
      @Schema(
              description =
                  "The link to show as a QR code and to open the app with, holding the server's"
                      + " public address and the scan code; null when no public address is"
                      + " configured, and the page builds it from its own address.",
              examples =
                  "signalhub://signin?server=https%3A%2F%2Fsignalhub.example.com&code=shsc1_")
          String uri,
      @Schema(required = true, description = "When both codes stop working.") Instant expiresAt,
      @Schema(
              required = true,
              description = "How the server named this browser from its User-Agent.",
              examples = "Firefox on Linux")
          String browserName) {}

  @Schema(name = "WebSignInState")
  public record Polled(
      @Schema(
              required = true,
              description =
                  "PENDING: waiting for a device. ASKED: a device is asking its user. SIGNED_IN:"
                      + " approved; this response sets the session cookie, once. CANCELLED: the"
                      + " user declined. EXPIRED: the codes ran out, or the sign-in was used.")
          WebSignInService.State state,
      @Schema(description = "When the codes stop working, or when the session ends if SIGNED_IN.")
          Instant expiresAt) {}

  @Schema(name = "WebSession", description = "A signed-in browser's own session.")
  public record Session(
      @Schema(
              required = true,
              description =
                  "Send this as the X-SignalHub-CSRF header on every state-changing request."
                      + " Only the page itself can read it.")
          String csrfToken,
      @Schema(required = true, description = "This browser's own registration.")
          ClientResponse client) {}

  @POST
  @Path("/sign-ins")
  @Operation(
      summary = "Start signing a browser in",
      description =
          "Called by the page, with no credential and no body. Gives the codes it shows for a"
              + " device to scan or type, and the secret it polls with. The browser is named"
              + " from its User-Agent. The codes live three minutes; the page asks again when"
              + " they run out. At most 200 sign-ins wait at once.")
  @APIResponse(
      responseCode = "201",
      description = "Started.",
      content = @Content(schema = @Schema(implementation = Started.class)))
  @APIResponse(
      responseCode = "429",
      description = "Too many sign-ins are waiting. Try again in a few minutes.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public Response start(
      @Parameter(hidden = true) @HeaderParam(HttpHeaders.USER_AGENT) String userAgent) {
    var started =
        signIns
            .start(userAgent)
            .orElseThrow(
                () ->
                    new ClientErrorException(
                        Response.status(429)
                            .entity(new ApiError("Too many sign-ins in progress", 429, List.of()))
                            .build()));
    return Response.status(Response.Status.CREATED)
        .header(HttpHeaders.CACHE_CONTROL, "no-store")
        .entity(
            new Started(
                started.id(),
                started.pollSecret(),
                started.code(),
                started.scanCode(),
                started.uri(),
                started.expiresAt(),
                started.browserName()))
        .build();
  }

  @GET
  @Path("/sign-ins/{id}")
  @SecurityRequirement(name = POLL_SCHEME)
  @Operation(
      summary = "Poll a sign-in",
      description =
          "Where the sign-in is. When a device has approved it, this response signs the browser"
              + " in: it creates the browser's client and sets the session cookie, once.")
  @APIResponse(
      responseCode = "200",
      description = "The state. SIGNED_IN comes with Set-Cookie.",
      content = @Content(schema = @Schema(implementation = Polled.class)))
  @APIResponse(
      responseCode = "401",
      description = "Unknown sign-in or wrong secret. The response does not say which.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public Response poll(
      @PathParam("id") UUID id,
      @Parameter(hidden = true) @HeaderParam(HttpHeaders.AUTHORIZATION) String authorization) {
    var polled =
        BearerToken.from(authorization)
            .flatMap(secret -> signIns.poll(id, secret))
            .orElseThrow(() -> new NotAuthorizedException(BearerToken.unauthorized()));
    var response =
        Response.ok(new Polled(polled.state(), polled.expiresAt()))
            .header(HttpHeaders.CACHE_CONTROL, "no-store");
    if (polled.key() != null) {
      response.header(HttpHeaders.SET_COOKIE, WebSession.cookie(polled.key()));
      // Fired after poll's transaction committed, so the browser it names exists.
      signedIn.fire(polled.signedIn());
    }
    return response.build();
  }

  @GET
  @Path("/session")
  @ClientAuthenticated
  @SecurityRequirement(name = SESSION_SCHEME)
  @Operation(
      summary = "Read this browser's session",
      description =
          "The signed-in browser's own registration, and the token it sends with every"
              + " state-changing request. Only for a browser's session cookie: a device's key is"
              + " refused.")
  @APIResponse(
      responseCode = "200",
      description = "The session.",
      content = @Content(schema = @Schema(implementation = Session.class)))
  @APIResponse(
      responseCode = "401",
      description = "No session, or it ended or was revoked.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public Response session() {
    var key =
        caller
            .sessionKey()
            .orElseThrow(() -> new NotAuthorizedException(BearerToken.unauthorized()));
    return Response.ok(new Session(WebSession.csrfToken(key), clients.get(caller.get())))
        .header(HttpHeaders.CACHE_CONTROL, "no-store")
        .build();
  }

  @POST
  @Path("/session/sign-out")
  @ClientAuthenticated
  @SecurityRequirement(name = SESSION_SCHEME)
  @Operation(
      summary = "Sign this browser out",
      description =
          "Revokes this browser's client, so its key stops working for good, and clears the"
              + " cookie. The user's devices and other browsers are untouched. The request has no"
              + " body.")
  @APIResponse(responseCode = "204", description = "Signed out.")
  @APIResponse(
      responseCode = "401",
      description = "No session, or it ended or was revoked already.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "403",
      description = "The request did not come from the page: no CSRF token, or another origin.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public Response signOut() {
    caller.sessionKey().orElseThrow(() -> new NotAuthorizedException(BearerToken.unauthorized()));
    clients.revoke(caller.get().id());
    return Response.noContent().header(HttpHeaders.SET_COOKIE, WebSession.expiredCookie()).build();
  }
}
