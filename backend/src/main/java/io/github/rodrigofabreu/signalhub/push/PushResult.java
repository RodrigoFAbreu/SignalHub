package io.github.rodrigofabreu.signalhub.push;

/** What a provider reports for one push. Only distinctions that delivery acts on are made. */
public enum PushResult {
  /** The provider accepted the push. It does not confirm that the device displayed it. */
  DELIVERED,
  /**
   * The provider says the token no longer addresses an installation (for example, the app was
   * uninstalled). The push target is removed, so it is not tried again.
   */
  INVALID_TARGET,
  /** Any other failure. The push target is kept; this push is not retried. */
  FAILED
}
