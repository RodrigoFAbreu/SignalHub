package io.github.rodrigofabreu.signalhub.client;

import io.github.rodrigofabreu.signalhub.producer.BearerToken;
import jakarta.annotation.Priority;
import jakarta.ws.rs.Priorities;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.container.ContainerRequestFilter;
import jakarta.ws.rs.core.HttpHeaders;
import jakarta.ws.rs.ext.Provider;

/**
 * Authenticates the client on {@link ClientAuthenticated} endpoints. Runs before the body is read,
 * so an unauthenticated request is rejected with 401 whatever its body contains.
 */
@Provider
@ClientAuthenticated
@Priority(Priorities.AUTHENTICATION)
class ClientAuthenticationFilter implements ContainerRequestFilter {

  private final ClientService clients;
  private final AuthenticatedClient authenticated;

  ClientAuthenticationFilter(ClientService clients, AuthenticatedClient authenticated) {
    this.clients = clients;
    this.authenticated = authenticated;
  }

  @Override
  public void filter(ContainerRequestContext request) {
    BearerToken.from(request.getHeaderString(HttpHeaders.AUTHORIZATION))
        .flatMap(clients::authenticate)
        .ifPresentOrElse(authenticated::set, () -> request.abortWith(BearerToken.unauthorized()));
  }
}
