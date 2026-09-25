package io.github.rodrigofabreu.signalhub.client;

import io.github.rodrigofabreu.signalhub.event.Category;
import io.github.rodrigofabreu.signalhub.event.Severity;
import java.util.List;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/**
 * Which events are pushed to a client. They decide only whether a push is sent: every event is
 * stored and listed whatever they say. Based on generic event fields only.
 */
@Schema(
    name = "PushPreferences",
    description =
        "Which events are pushed to the client. Events that are not pushed are still stored and"
            + " listed.")
public record PushPreferences(
    @Schema(
            required = true,
            description = "False pauses every push to the client; its push target is kept.")
        boolean enabled,
    @Schema(required = true, description = "Events below this severity are not pushed.")
        Severity minimumSeverity,
    @Schema(required = true, description = "Events with these categories are not pushed.")
        List<Category> mutedCategories,
    @Schema(required = true, description = "Events of these producers are not pushed.")
        List<UUID> mutedProducerIds) {

  /** What a client starts with: every event is pushed. */
  public static final PushPreferences DEFAULT =
      new PushPreferences(true, Severity.LOW, List.of(), List.of());

  /** Most producers a client can mute. */
  public static final int MAX_MUTED_PRODUCERS = 100;

  public PushPreferences {
    // Sorted and without duplicates, so equal preferences always read the same.
    mutedCategories = List.copyOf(mutedCategories.stream().distinct().sorted().toList());
    mutedProducerIds = List.copyOf(mutedProducerIds.stream().distinct().sorted().toList());
  }

  /** Whether an event with these generic fields is pushed to the client. */
  public boolean allow(Category category, Severity severity, UUID producerId) {
    return enabled
        && severity.compareTo(minimumSeverity) >= 0
        && !mutedCategories.contains(category)
        && !mutedProducerIds.contains(producerId);
  }
}
