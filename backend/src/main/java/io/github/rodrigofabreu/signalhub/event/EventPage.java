package io.github.rodrigofabreu.signalhub.event;

import java.util.List;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** One page of the event listing, newest first. */
@Schema(name = "EventPage", description = "One page of events, newest first.")
public record EventPage(
    @Schema(required = true, description = "The events on this page, newest first.")
        List<EventResponse> items,
    @Schema(
            description =
                "Opaque cursor for the next page: pass it as the cursor parameter together with"
                    + " the same filters. Null when there are no more events.",
            examples = "MToxNzkwMzM3NzgxNDgyMTEzOjAxOTk3ZDVlLThhM2MtN2IxZS05ZjJhLTRjNmQ4ZTBmMWEyYg",
            nullable = true)
        String nextCursor) {

  public EventPage {
    items = List.copyOf(items);
  }
}
