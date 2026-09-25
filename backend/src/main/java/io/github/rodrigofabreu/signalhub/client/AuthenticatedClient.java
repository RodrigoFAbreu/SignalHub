package io.github.rodrigofabreu.signalhub.client;

import jakarta.enterprise.context.RequestScoped;

/**
 * The client that authenticated the current request, set by {@link ClientAuthenticationFilter} on
 * endpoints marked {@link ClientAuthenticated}.
 */
@RequestScoped
public class AuthenticatedClient {

  private ClientIdentity identity;

  void set(ClientIdentity identity) {
    this.identity = identity;
  }

  /** Fails closed if the endpoint was not protected by client authentication. */
  public ClientIdentity get() {
    if (identity == null) {
      throw new IllegalStateException("request has no authenticated client");
    }
    return identity;
  }
}
