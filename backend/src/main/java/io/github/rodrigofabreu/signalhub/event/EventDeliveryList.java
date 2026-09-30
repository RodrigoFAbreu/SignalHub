package io.github.rodrigofabreu.signalhub.event;

import java.util.List;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/**
 * Response of {@code GET /api/v1/admin/events/{id}/deliveries}. An object rather than a bare array,
 * so fields can be added later without breaking the contract.
 */
@Schema(
    name = "EventDeliveryList",
    description = "Every delivery record of the event, oldest first.")
public record EventDeliveryList(
    @Schema(required = true, description = "The records, oldest first.")
        List<EventDelivery> items) {

  public EventDeliveryList {
    items = List.copyOf(items);
  }
}
