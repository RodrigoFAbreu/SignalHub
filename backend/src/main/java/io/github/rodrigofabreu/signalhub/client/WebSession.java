package io.github.rodrigofabreu.signalhub.client;

import io.github.rodrigofabreu.signalhub.api.ApiError;
import io.github.rodrigofabreu.signalhub.producer.BearerToken;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Duration;
import java.util.Base64;
import java.util.List;
import java.util.Set;
import org.jboss.logging.Logger;

/**
 * A browser's session: the client key of a signed-in browser, held only in an {@code HttpOnly},
 * {@code Secure}, {@code SameSite=Strict} cookie, so no script can read it. It authenticates the
 * same client API as a bearer key does, but state-changing requests made with it must also prove
 * they come from the page itself (see {@link #csrfRefusal}).
 */
@ApplicationScoped
class WebSession {

  private static final Logger LOG = Logger.getLogger(WebSession.class);

  // The __Host- prefix makes a browser refuse the cookie unless it is Secure, has Path=/ and no
  // Domain, so another subdomain cannot plant or overwrite it.
  static final String COOKIE = "__Host-signalhub_session";
  static final String CSRF_HEADER = "X-SignalHub-CSRF";

  /** A browser's sign-in lasts exactly this long, however it is used. */
  static final Duration LIFETIME = Duration.ofDays(30);

  private static final Set<String> SAFE_METHODS = Set.of("GET", "HEAD", "OPTIONS");

  private final ClientService clients;

  WebSession(ClientService clients) {
    this.clients = clients;
  }

  /**
   * Authenticates a request that carries no bearer key by its session cookie: sets the client, or
   * aborts with 401 (no, unknown, revoked or ended session, or a cookie holding a device's key) or
   * 403 (a state-changing request that does not come from the page).
   */
  void authenticate(ContainerRequestContext request, AuthenticatedClient authenticated) {
    var cookie = request.getCookies().get(COOKIE);
    if (cookie == null) {
      request.abortWith(BearerToken.unauthorized());
      return;
    }
    var identity =
        clients.authenticate(cookie.getValue()).filter(found -> found.kind() == ClientKind.BROWSER);
    if (identity.isEmpty()) {
      request.abortWith(BearerToken.unauthorized());
      return;
    }
    if (!SAFE_METHODS.contains(request.getMethod()) && !csrfAccepted(request, cookie.getValue())) {
      LOG.debugf("Refused a cross-site request of browser %s", identity.get().id());
      request.abortWith(csrfRefusal());
      return;
    }
    authenticated.setFromCookie(identity.get(), cookie.getValue());
  }

  /**
   * A state-changing request is accepted only if it carries the token derived from the session
   * (which only a script of the page can read, through {@code GET /api/v1/web/session}, as no other
   * origin may read a response) and, if the browser says where it came from, comes from the same
   * host. Either alone would do; both together survive a mistake in the other.
   */
  private static boolean csrfAccepted(ContainerRequestContext request, String sessionKey) {
    var presented = request.getHeaderString(CSRF_HEADER);
    if (presented == null
        || !MessageDigest.isEqual(
            presented.getBytes(StandardCharsets.UTF_8),
            csrfToken(sessionKey).getBytes(StandardCharsets.UTF_8))) {
      return false;
    }
    var origin = request.getHeaderString("Origin");
    if (origin == null) {
      return true;
    }
    try {
      var authority = URI.create(origin).getAuthority();
      return authority != null && authority.equalsIgnoreCase(request.getHeaderString("Host"));
    } catch (RuntimeException e) {
      return false;
    }
  }

  private static Response csrfRefusal() {
    return Response.status(Response.Status.FORBIDDEN)
        .type(MediaType.APPLICATION_JSON_TYPE)
        .entity(new ApiError("Request refused", 403, List.of()))
        .build();
  }

  /**
   * The token a page sends in {@link #CSRF_HEADER}: derived from the session, so it needs no store.
   */
  static String csrfToken(String sessionKey) {
    try {
      var digest =
          MessageDigest.getInstance("SHA-256")
              .digest(("signalhub-csrf-v1:" + sessionKey).getBytes(StandardCharsets.UTF_8));
      return Base64.getUrlEncoder().withoutPadding().encodeToString(digest);
    } catch (NoSuchAlgorithmException e) {
      throw new IllegalStateException("every Java platform provides SHA-256", e);
    }
  }

  /** The Set-Cookie value that holds the session key for the session's whole life. */
  static String cookie(String sessionKey) {
    return header(sessionKey, LIFETIME.toSeconds());
  }

  /** The Set-Cookie value that ends the session in the browser. */
  static String expiredCookie() {
    return header("", 0);
  }

  // Written out rather than built by JAX-RS, which writes the obsolete "Version=1" form. The
  // __Host- prefix needs Secure, Path=/ and no Domain; HttpOnly keeps the key from scripts and
  // SameSite=Strict from other sites' requests.
  private static String header(String value, long maxAgeSeconds) {
    return COOKIE
        + "="
        + value
        + "; Max-Age="
        + maxAgeSeconds
        + "; Path=/; Secure; HttpOnly; SameSite=Strict";
  }
}
