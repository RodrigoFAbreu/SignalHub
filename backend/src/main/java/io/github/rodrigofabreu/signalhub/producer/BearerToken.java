package io.github.rodrigofabreu.signalhub.producer;

import io.github.rodrigofabreu.signalhub.api.ApiError;
import jakarta.ws.rs.core.HttpHeaders;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.List;
import java.util.Optional;

/** Reads {@code Authorization: Bearer <token>} (RFC 6750) and builds the matching 401. */
public final class BearerToken {

  private static final String SCHEME = "Bearer";

  private BearerToken() {}

  /**
   * The token, or empty if the header is absent or not a single well-formed Bearer credential. The
   * scheme is case-insensitive; the token itself is checked by the caller.
   */
  public static Optional<String> from(String authorization) {
    if (authorization == null
        || authorization.length() <= SCHEME.length() + 1
        || !authorization.regionMatches(true, 0, SCHEME, 0, SCHEME.length())
        || authorization.charAt(SCHEME.length()) != ' ') {
      return Optional.empty();
    }
    return Optional.of(authorization.substring(SCHEME.length() + 1));
  }

  /**
   * The one response for every authentication failure, so callers cannot tell a missing, malformed,
   * unknown, revoked or disabled credential apart.
   */
  public static Response unauthorized() {
    return Response.status(Response.Status.UNAUTHORIZED)
        .header(HttpHeaders.WWW_AUTHENTICATE, SCHEME + " realm=\"signalhub\"")
        .type(MediaType.APPLICATION_JSON_TYPE)
        .entity(new ApiError("Unauthorized", 401, List.of()))
        .build();
  }
}
