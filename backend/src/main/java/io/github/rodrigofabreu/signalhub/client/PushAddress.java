package io.github.rodrigofabreu.signalhub.client;

import java.util.Objects;

/** A client's push target as delivery needs it: the provider name and the opaque token. */
public record PushAddress(String provider, String token) {

  public PushAddress {
    Objects.requireNonNull(provider, "provider");
    Objects.requireNonNull(token, "token");
  }

  // The token addresses a device; keep it out of logs if this is ever printed.
  @Override
  public String toString() {
    return "PushAddress[provider=" + provider + "]";
  }
}
