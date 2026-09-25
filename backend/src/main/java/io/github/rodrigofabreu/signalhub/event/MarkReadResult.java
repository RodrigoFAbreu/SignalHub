package io.github.rodrigofabreu.signalhub.event;

import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** Response of {@code POST /api/v1/events/read}. */
@Schema(name = "MarkReadResult", description = "How many events were marked read.")
public record MarkReadResult(
    @Schema(
            required = true,
            description = "Events that were unread and are now read.",
            examples = "12")
        long marked) {}
