package io.github.rodrigofabreu.signalhub.event;

import io.github.rodrigofabreu.signalhub.push.DeliveryResult;

/** How one push of an event to one client went, as its delivery record says. */
public enum DeliveryOutcome {
  /** The provider accepted the push. */
  DELIVERED,
  /** Nothing was sent: the client's push preferences keep the event from it. */
  FILTERED,
  /** Nothing was sent: the client has no push target, or was revoked meanwhile. */
  NO_TARGET,
  /** Nothing was sent: the server has no provider of the push target's name. */
  UNSUPPORTED_PROVIDER,
  /** The provider rejected the target for good, and it was removed. */
  INVALID_TARGET,
  /** The send failed but may succeed later; it is retried while attempts remain. */
  TRANSIENT_FAILURE,
  /** The provider refused the push, and repeating it will not help. */
  PERMANENT_FAILURE;

  static DeliveryOutcome of(DeliveryResult result) {
    return switch (result) {
      case DELIVERED -> DELIVERED;
      case NO_TARGET -> NO_TARGET;
      case UNSUPPORTED_PROVIDER -> UNSUPPORTED_PROVIDER;
      case INVALID_TARGET -> INVALID_TARGET;
      case TRANSIENT_FAILURE -> TRANSIENT_FAILURE;
      case PERMANENT_FAILURE -> PERMANENT_FAILURE;
    };
  }
}
