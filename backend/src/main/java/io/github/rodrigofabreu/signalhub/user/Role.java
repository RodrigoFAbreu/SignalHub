package io.github.rodrigofabreu.signalhub.user;

/**
 * What a user may do with devices. Producers and subscriptions are open to every role. The role is
 * the user's, never a device's: a device is an admin device exactly when its user is an {@link
 * #ADMIN}.
 */
public enum Role {
  /** Owns producers and subscribes; cannot pair, rename, revoke or delete devices. */
  BASIC,
  /** As {@link #BASIC}, and manages their own devices. */
  MOD,
  /**
   * As {@link #MOD}, and sees every device, manages those of users who are not admins, and invites
   * users. Granted and taken away only by the operator, with the admin token.
   */
  ADMIN
}
