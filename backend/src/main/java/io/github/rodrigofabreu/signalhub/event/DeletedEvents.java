package io.github.rodrigofabreu.signalhub.event;

import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** Response of {@code POST /api/v1/admin/events/delete}. */
@Schema(
    name = "DeletedEvents",
    description = "How many events were deleted, or with dryRun, how many would be.")
public record DeletedEvents(
    @Schema(
            required = true,
            description =
                "Events deleted; with dryRun, the events that match now and would be deleted.",
            examples = "12")
        long count,
    @Schema(required = true, description = "Whether this was a dry run, which deletes nothing.")
        boolean dryRun,
    @Schema(
            required = true,
            description =
                "How many of the counted events ask a question, so a confirmation can say that"
                    + " some are open questions. Counted with dryRun too.",
            examples = "2")
        long asking) {}
