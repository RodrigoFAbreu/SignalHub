package io.github.rodrigofabreu.signalhub.client;

import io.github.rodrigofabreu.signalhub.push.DeliveryResult;
import java.time.Instant;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.enums.SchemaType;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/**
 * A client's latest push results, for the operator: the last push its provider accepted, the last
 * one that failed, and the pushes waiting to be sent again. Only the latest results, not a history.
 */
@Schema(
    name = "PushStatus",
    description =
        "The client's latest push results. Each send overwrites the last success or the last"
            + " failure; there is no history. A send that found no push target is not recorded.")
public record PushStatus(
    @Schema(description = "The last push the provider accepted; null if there has been none.")
        Success lastSuccess,
    @Schema(description = "The last push that failed; null if none has.") Failure lastFailure,
    @Schema(
            required = true,
            description =
                "Pushes to this client that failed temporarily and wait to be sent again. A"
                    + " revoked client's are dropped when due.",
            examples = "0")
        long pendingRetries) {

  @Schema(name = "PushSuccess", description = "A push the provider accepted.")
  public record Success(
      @Schema(required = true, examples = "2026-09-25T12:00:00.123456Z") Instant at,
      @Schema(
              required = true,
              description = "The pushed event. It may have been deleted since.",
              examples = "01997d5e-8a3c-7b1e-9f2a-4c6d8e0f1a2b")
          UUID eventId) {}

  @Schema(name = "PushFailure", description = "A push that failed. The push token is never shown.")
  public record Failure(
      @Schema(required = true, examples = "2026-09-25T12:00:00.123456Z") Instant at,
      @Schema(
              required = true,
              description = "The event whose push failed. It may have been deleted since.",
              examples = "01997d5e-8a3c-7b1e-9f2a-4c6d8e0f1a2b")
          UUID eventId,
      @Schema(
              required = true,
              type = SchemaType.STRING,
              enumeration = {
                "UNSUPPORTED_PROVIDER",
                "INVALID_TARGET",
                "TRANSIENT_FAILURE",
                "PERMANENT_FAILURE"
              },
              description =
                  "Why it failed. UNSUPPORTED_PROVIDER: the server has no provider of the push"
                      + " target's name. INVALID_TARGET: the provider rejected the target for"
                      + " good, and it was removed. TRANSIENT_FAILURE: the send may succeed later"
                      + " and is retried. PERMANENT_FAILURE: the provider refused the push and"
                      + " repeating it will not help.",
              examples = "PERMANENT_FAILURE")
          DeliveryResult result) {}
}
