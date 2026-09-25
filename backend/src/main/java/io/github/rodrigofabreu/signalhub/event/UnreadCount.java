package io.github.rodrigofabreu.signalhub.event;

import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** Response of {@code GET /api/v1/events/unread-count}. */
@Schema(name = "UnreadCount", description = "How many events are unread.")
public record UnreadCount(
    @Schema(required = true, description = "Unread events.", examples = "3") long unread) {}
