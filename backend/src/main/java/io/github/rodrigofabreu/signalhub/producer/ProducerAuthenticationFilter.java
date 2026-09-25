package io.github.rodrigofabreu.signalhub.producer;

import jakarta.annotation.Priority;
import jakarta.ws.rs.Priorities;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.container.ContainerRequestFilter;
import jakarta.ws.rs.core.HttpHeaders;
import jakarta.ws.rs.ext.Provider;

/**
 * Authenticates the producer on {@link ProducerAuthenticated} endpoints. Runs before the body is
 * read, so an unauthenticated request is rejected with 401 whatever its body contains.
 */
@Provider
@ProducerAuthenticated
@Priority(Priorities.AUTHENTICATION)
class ProducerAuthenticationFilter implements ContainerRequestFilter {

  private final ProducerService producers;
  private final AuthenticatedProducer authenticated;

  ProducerAuthenticationFilter(ProducerService producers, AuthenticatedProducer authenticated) {
    this.producers = producers;
    this.authenticated = authenticated;
  }

  @Override
  public void filter(ContainerRequestContext request) {
    BearerToken.from(request.getHeaderString(HttpHeaders.AUTHORIZATION))
        .flatMap(producers::authenticate)
        .ifPresentOrElse(authenticated::set, () -> request.abortWith(BearerToken.unauthorized()));
  }
}
