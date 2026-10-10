package io.github.rodrigofabreu.signalhub.event;

import java.time.Instant;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** One delivery record of a user's device, with the event it was for. */
@Schema(
    name = "UserDelivery",
    description =
        "One attempt to push an event to one of the user's devices, and how it went. The push"
            + " token is never shown.")
public record UserDelivery(
    @Schema(required = true, examples = "01997d5e-8a3c-7b1e-9f2a-4c6d8e0f1a2b") UUID eventId,
    @Schema(required = true, description = "The event's title.", examples = "Nightly build failed")
        String eventTitle,
    @Schema(required = true, examples = "01997d5e-8a3c-7b1e-9f2a-4c6d8e0f1a2d") UUID clientId,
    @Schema(required = true, description = "The device's name now.", examples = "Pixel 9")
        String clientName,
    @Schema(required = true, description = "1 for the first dispatch, then one per retry.")
        int attempt,
    @Schema(required = true, description = "As in an event's delivery records.")
        DeliveryOutcome outcome,
    @Schema(description = "Why, when there is more to say; null otherwise.") String detail,
    @Schema(required = true, examples = "2026-09-25T12:00:00.123456Z") Instant at) {}
