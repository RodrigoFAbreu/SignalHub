package io.github.rodrigofabreu.signalhub.push;

import java.util.Objects;

/**
 * What a provider reports for one send. The status is all that delivery logic depends on; {@code
 * detail} is for logs only and must never contain the push token or credentials.
 */
public record PushOutcome(Status status, String detail) {

  public enum Status {
    /** The provider accepted the message for the target. */
    DELIVERED,
    /**
     * The provider says the target no longer exists or never belonged to this sender, e.g. the app
     * was uninstalled. Sending to it again cannot succeed, so SignalHub forgets the target.
     */
    INVALID_TARGET,
    /** Temporary failure (unavailable, rate-limited, timeout); the same send may succeed later. */
    TRANSIENT_FAILURE,
    /**
     * Failure that retrying the same send will not fix, but that does not condemn the target, e.g.
     * a rejected payload or a provider misconfiguration.
     */
    PERMANENT_FAILURE
  }

  public PushOutcome {
    Objects.requireNonNull(status, "status");
    detail = detail == null ? "" : detail;
  }

  public static PushOutcome delivered() {
    return new PushOutcome(Status.DELIVERED, "");
  }
}
