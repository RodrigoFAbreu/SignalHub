package io.github.rodrigofabreu.signalhub.event;

import java.time.Instant;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/**
 * One of an event's delivery records: one push attempt to one client (of one user), and how it
 * went.
 */
@Schema(
    name = "EventDelivery",
    description =
        "One attempt to push the event to one client, and how it went. The push token is never"
            + " shown.")
public record EventDelivery(
    @Schema(required = true, examples = "01997d5e-8a3c-7b1e-9f2a-4c6d8e0f1a2b") UUID clientId,
    @Schema(required = true, description = "The client's name now.", examples = "Pixel 9")
        String clientName,
    @Schema(
            required = true,
            description = "The user the client belongs to.",
            examples = "01997d5e-8a3c-7b1e-9f2a-4c6d8e0f1a2c")
        UUID userId,
    @Schema(required = true, description = "The user's name now.", examples = "Anna")
        String userName,
    @Schema(
            required = true,
            description = "1 for the first dispatch of the event, then one more for each retry.",
            examples = "1")
        int attempt,
    @Schema(
            required = true,
            description =
                "DELIVERED: the provider accepted the push. FILTERED: the client's push"
                    + " preferences keep the event from it, so nothing was sent. NO_TARGET: the"
                    + " client has no push target, or was revoked, so nothing was sent."
                    + " UNSUPPORTED_PROVIDER: the server has no provider of the push target's"
                    + " name. INVALID_TARGET: the provider rejected the target for good, and it"
                    + " was removed. TRANSIENT_FAILURE: the send may succeed later and is retried"
                    + " while attempts remain. PERMANENT_FAILURE: the provider refused the push"
                    + " and retrying will not help. Later releases may add values.")
        DeliveryOutcome outcome,
    @Schema(
            description =
                "Why, when there is more to say: the provider's reason for a failure, or the"
                    + " preference that filtered the event out; null otherwise.",
            examples = "HTTP 503 UNAVAILABLE")
        String detail,
    @Schema(required = true, examples = "2026-09-25T12:00:00.123456Z") Instant at) {}
