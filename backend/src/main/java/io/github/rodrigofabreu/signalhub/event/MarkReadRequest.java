package io.github.rodrigofabreu.signalhub.event;

import jakarta.validation.constraints.NotNull;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** Body of {@code POST /api/v1/events/read}. */
@Schema(
    name = "MarkReadRequest",
    description =
        "Marks read every unread event up to a given one: the event itself and every event before"
            + " it in listing order. Events after it stay unread.")
public record MarkReadRequest(
    @Schema(
            required = true,
            description =
                "Canonical ID of the newest event to mark read, usually the first event the"
                    + " client shows.",
            examples = "01997d5e-8a3c-7b1e-9f2a-4c6d8e0f1a2b")
        @NotNull
        UUID through) {}
