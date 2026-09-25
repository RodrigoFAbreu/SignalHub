package io.github.rodrigofabreu.signalhub.push;

/** The result of asking {@link PushDelivery} to push to one client. */
public enum DeliveryResult {
  /** The provider accepted the message. */
  DELIVERED,
  /** Nothing was sent: the client does not exist, is revoked, or has no push target. */
  NO_TARGET,
  /** Nothing was sent: no active provider has the name of the client's push target. */
  UNSUPPORTED_PROVIDER,
  /** The provider rejected the target for good; the client's push target was removed. */
  INVALID_TARGET,
  /** The send failed but may succeed later. */
  TRANSIENT_FAILURE,
  /** The send failed and repeating it will not help; the target is kept. */
  PERMANENT_FAILURE
}
