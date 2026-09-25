package io.github.rodrigofabreu.signalhub.client;

import java.util.UUID;

/** A client's current push target, as delivery needs it. The token is omitted from toString(). */
public record PushTarget(UUID clientId, String provider, String token) {

  @Override
  public String toString() {
    return "PushTarget[clientId=" + clientId + ", provider=" + provider + "]";
  }
}
