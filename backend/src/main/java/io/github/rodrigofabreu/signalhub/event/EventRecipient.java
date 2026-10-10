package io.github.rodrigofabreu.signalhub.event;

import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** A user an event reached: one subscribed to its producer. */
@Schema(
    name = "EventRecipient",
    description = "A user who receives the event's producer's events, by subscription.")
public record EventRecipient(
    @Schema(required = true, examples = "01997d5e-8a3c-7b1e-9f2a-4c6d8e0f1a2c") UUID id,
    @Schema(required = true, description = "The user's name now.", examples = "Anna") String name,
    @Schema(required = true, description = "Whether the user owns the event's producer.")
        boolean owner) {}
