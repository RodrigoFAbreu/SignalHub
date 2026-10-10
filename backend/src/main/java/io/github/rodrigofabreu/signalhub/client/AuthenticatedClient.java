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
  private String sessionKey;

  void set(ClientIdentity identity) {
    this.identity = identity;
  }

  /** The client of a signed-in browser, authenticated by its session cookie holding this key. */
  void setFromCookie(ClientIdentity identity, String sessionKey) {
    this.identity = identity;
    this.sessionKey = sessionKey;
  }

  /** The session key, if the request was authenticated by a browser's session cookie. */
  Optional<String> sessionKey() {
    return Optional.ofNullable(sessionKey);
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
