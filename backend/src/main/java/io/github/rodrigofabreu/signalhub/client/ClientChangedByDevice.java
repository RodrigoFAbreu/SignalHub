package io.github.rodrigofabreu.signalhub.client;

import java.util.UUID;

/**
 * Fired, as a CDI event, once a device's change to another client is committed, so the devices that
 * should know can be told who did what: those of {@code userId}, the user the changed client
 * belongs to, and of the admins. Never carries a key or a push token.
 */
public record ClientChangedByDevice(
    UUID byClientId, String byName, UUID clientId, String name, UUID userId, Change change) {

  /** What the device did. */
  public enum Change {
    REVOKED
  }
}
