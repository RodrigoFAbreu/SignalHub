package io.github.rodrigofabreu.signalhub.producer;

import jakarta.enterprise.context.RequestScoped;

/**
 * The producer that authenticated the current request, set by {@link ProducerAuthenticationFilter}
 * on endpoints marked {@link ProducerAuthenticated}.
 */
@RequestScoped
public class AuthenticatedProducer {

  private ProducerIdentity identity;

  void set(ProducerIdentity identity) {
    this.identity = identity;
  }

  /** Fails closed if the endpoint was not protected by producer authentication. */
  public ProducerIdentity get() {
    if (identity == null) {
      throw new IllegalStateException("request has no authenticated producer");
    }
    return identity;
  }
}
