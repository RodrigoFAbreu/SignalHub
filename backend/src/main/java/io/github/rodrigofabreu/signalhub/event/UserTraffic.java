package io.github.rodrigofabreu.signalhub.event;

import java.util.List;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** Response of {@code GET /api/v1/admin/users/{id}/traffic}. */
@Schema(
    name = "UserTraffic",
    description = "A user's recent events and deliveries, newest first, for the operator.")
public record UserTraffic(
    @Schema(
            required = true,
            description =
                "The newest events of the producers the user owns or is subscribed to, in the"
                    + " operator's read state.")
        List<EventResponse> events,
    @Schema(
            required = true,
            description = "The newest delivery records of the user's devices, across events.")
        List<UserDelivery> deliveries) {

  public UserTraffic {
    events = List.copyOf(events);
    deliveries = List.copyOf(deliveries);
  }
}
