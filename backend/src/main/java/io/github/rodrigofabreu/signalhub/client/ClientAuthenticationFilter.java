package io.github.rodrigofabreu.signalhub.client;

import io.github.rodrigofabreu.signalhub.producer.BearerToken;
import jakarta.annotation.Priority;
import jakarta.ws.rs.Priorities;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.container.ContainerRequestFilter;
import jakarta.ws.rs.core.HttpHeaders;
import jakarta.ws.rs.ext.Provider;

/**
 * Authenticates the client on {@link ClientAuthenticated} endpoints, by its bearer key or, for a
 * signed-in browser without one, its session cookie. Runs before the body is read, so an
 * unauthenticated request is rejected with 401 whatever its body contains.
 */
@Provider
@ClientAuthenticated
@Priority(Priorities.AUTHENTICATION)
class ClientAuthenticationFilter implements ContainerRequestFilter {

  private final ClientService clients;
  private final AuthenticatedClient authenticated;
  private final WebSession session;

  ClientAuthenticationFilter(
      ClientService clients, AuthenticatedClient authenticated, WebSession session) {
    this.clients = clients;
    this.authenticated = authenticated;
    this.session = session;
  }

  @Override
  public void filter(ContainerRequestContext request) {
    if (request.getHeaderString(HttpHeaders.AUTHORIZATION) == null) {
      // A browser has no key to send: its session cookie stands in for the header.
      session.authenticate(request, authenticated);
      return;
    }
    BearerToken.from(request.getHeaderString(HttpHeaders.AUTHORIZATION))
        .flatMap(clients::authenticate)
        .ifPresentOrElse(authenticated::set, () -> request.abortWith(BearerToken.unauthorized()));
  }
}
