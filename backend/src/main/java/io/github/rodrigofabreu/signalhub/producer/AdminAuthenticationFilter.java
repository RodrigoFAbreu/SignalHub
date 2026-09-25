package io.github.rodrigofabreu.signalhub.producer;

import io.github.rodrigofabreu.signalhub.api.ApiError;
import jakarta.annotation.Priority;
import jakarta.ws.rs.Priorities;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.container.ContainerRequestFilter;
import jakarta.ws.rs.core.HttpHeaders;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.ext.Provider;
import java.util.List;
import org.jboss.logging.Logger;

/**
 * Guards {@link AdminOnly} endpoints: 404 while no admin token is configured, as if the management
 * API did not exist, and 401 unless the request carries the token.
 */
@Provider
@AdminOnly
@Priority(Priorities.AUTHENTICATION)
class AdminAuthenticationFilter implements ContainerRequestFilter {

  private static final Logger LOG = Logger.getLogger(AdminAuthenticationFilter.class);

  private final AdminToken token;

  AdminAuthenticationFilter(AdminToken token) {
    this.token = token;
  }

  @Override
  public void filter(ContainerRequestContext request) {
    if (!token.enabled()) {
      request.abortWith(
          Response.status(Response.Status.NOT_FOUND)
              .type(MediaType.APPLICATION_JSON_TYPE)
              .entity(new ApiError("Not found", 404, List.of()))
              .build());
      return;
    }
    var presented = BearerToken.from(request.getHeaderString(HttpHeaders.AUTHORIZATION));
    if (presented.isEmpty() || !token.matches(presented.get())) {
      LOG.debug("Rejected management API request: missing or wrong admin token");
      request.abortWith(BearerToken.unauthorized());
    }
  }
}
