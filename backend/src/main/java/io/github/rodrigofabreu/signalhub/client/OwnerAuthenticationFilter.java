package io.github.rodrigofabreu.signalhub.client;

import io.github.rodrigofabreu.signalhub.producer.AdminToken;
import io.github.rodrigofabreu.signalhub.producer.BearerToken;
import jakarta.annotation.Priority;
import jakarta.ws.rs.Priorities;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.container.ContainerRequestFilter;
import jakarta.ws.rs.core.HttpHeaders;
import jakarta.ws.rs.ext.Provider;
import org.jboss.logging.Logger;

/**
 * Guards {@link OwnerAuthenticated} endpoints: a client key or the admin token, else the same 401
 * as every other credential failure. Unlike the management API these endpoints exist without an
 * admin token, because clients read through them.
 */
@Provider
@OwnerAuthenticated
@Priority(Priorities.AUTHENTICATION)
class OwnerAuthenticationFilter implements ContainerRequestFilter {

  private static final Logger LOG = Logger.getLogger(OwnerAuthenticationFilter.class);

  private final ClientService clients;
  private final AdminToken adminToken;

  OwnerAuthenticationFilter(ClientService clients, AdminToken adminToken) {
    this.clients = clients;
    this.adminToken = adminToken;
  }

  @Override
  public void filter(ContainerRequestContext request) {
    var presented = BearerToken.from(request.getHeaderString(HttpHeaders.AUTHORIZATION));
    if (presented.isEmpty()) {
      LOG.debug("Rejected owner credential: no bearer token");
      request.abortWith(BearerToken.unauthorized());
      return;
    }
    var token = presented.get();
    if (!adminToken.matches(token) && clients.authenticate(token).isEmpty()) {
      LOG.debug("Rejected owner credential: not a valid client key or admin token");
      request.abortWith(BearerToken.unauthorized());
    }
  }
}
