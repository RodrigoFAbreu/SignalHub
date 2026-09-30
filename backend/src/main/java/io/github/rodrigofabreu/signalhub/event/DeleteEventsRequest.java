package io.github.rodrigofabreu.signalhub.event;

import com.fasterxml.jackson.databind.annotation.JsonDeserialize;
import io.github.rodrigofabreu.signalhub.api.IsoOffsetDateTimeDeserializer;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/**
 * Body of {@code POST /api/v1/admin/events/delete}: a selection of events, or a filter, to delete
 * or, with {@code dryRun}, to count.
 */
@Schema(
    name = "DeleteEventsRequest",
    description =
        "The events to delete: either a selection (ids) or a filter (producerId, createdBefore or"
            + " both, which must then both match), never both. With dryRun, nothing is deleted"
            + " and the answer says how many events would be.")
public record DeleteEventsRequest(
    @Schema(
            description =
                "Canonical IDs of the events to delete, 1 to "
                    + DeleteEventsRequest.MAX_IDS
                    + ". IDs of events that do not exist (deleted already) are skipped.",
            maxItems = DeleteEventsRequest.MAX_IDS,
            examples = "[\"01997d5e-8a3c-7b1e-9f2a-4c6d8e0f1a2b\"]")
        @Size(min = 1, max = MAX_IDS)
        List<@NotNull UUID> ids,
    @Schema(
            description = "Only events of this producer (canonical ID).",
            examples = "01997d5e-1111-7b1e-9f2a-4c6d8e0f1a2b")
        UUID producerId,
    @Schema(
            description =
                "Only events created before this time (exclusive), by the server's createdAt."
                    + " ISO-8601 with a UTC offset.",
            examples = "2026-09-01T00:00:00Z")
        @JsonDeserialize(using = IsoOffsetDateTimeDeserializer.class)
        @SupportedTimestamp
        OffsetDateTime createdBefore,
    @Schema(
            description =
                "true counts the events that would be deleted and deletes none. Optional; false"
                    + " when omitted or null.")
        Boolean dryRun) {

  static final int MAX_IDS = 100;

  public DeleteEventsRequest {
    // Copied without List.copyOf, which throws on a null ID before validation can report it.
    ids = ids == null ? null : Collections.unmodifiableList(new ArrayList<>(ids));
  }

  boolean selection() {
    return ids != null;
  }

  boolean filter() {
    return producerId != null || createdBefore != null;
  }

  boolean dryRunRequested() {
    return Boolean.TRUE.equals(dryRun);
  }
}
