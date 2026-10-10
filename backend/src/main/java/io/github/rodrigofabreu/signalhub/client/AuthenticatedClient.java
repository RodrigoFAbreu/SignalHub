package io.github.rodrigofabreu.signalhub.client;

import jakarta.enterprise.context.RequestScoped;
import java.util.Optional;

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

  /**
   * The client, or empty on an endpoint the operator may also call with the admin token, who acts
   * for no user.
   */
  public Optional<ClientIdentity> current() {
    return Optional.ofNullable(identity);
  }

  /** Fails closed if the endpoint was not protected by client authentication. */
  public ClientIdentity get() {
    if (identity == null) {
      throw new IllegalStateException("request has no authenticated client");
    }
    return identity;
  }
}
