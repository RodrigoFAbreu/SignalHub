package io.github.rodrigofabreu.signalhub.client;

import java.util.UUID;

/**
 * Fired, as a CDI event, once an admin device's change to another client is committed, so the
 * owner's devices can be told who did what. Never carries a key or a push token.
 */
public record ClientChangedByDevice(
    UUID byClientId, String byName, UUID clientId, String name, Change change) {

  /** What the admin device did. */
  public enum Change {
    MADE_ADMIN,
    REVOKED
  }
}
