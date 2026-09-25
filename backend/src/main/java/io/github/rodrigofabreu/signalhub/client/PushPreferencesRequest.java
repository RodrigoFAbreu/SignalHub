package io.github.rodrigofabreu.signalhub.client;

import static java.util.Collections.unmodifiableList;

import io.github.rodrigofabreu.signalhub.event.Category;
import io.github.rodrigofabreu.signalhub.event.Severity;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/**
 * Body of {@code PUT /api/v1/client/push-preferences}. It replaces all preferences; a field that is
 * absent or null takes its default, so {@code {}} restores pushing every event.
 */
@Schema(
    name = "PushPreferencesRequest",
    description =
        "The client's new push preferences, replacing the previous ones. An absent or null field"
            + " takes its default.")
public record PushPreferencesRequest(
    @Schema(description = "False pauses every push to the client. Default true.") Boolean enabled,
    @Schema(
            description = "Events below this severity are not pushed. Default LOW.",
            examples = "HIGH")
        Severity minimumSeverity,
    @Schema(
            description =
                "Events with these categories are not pushed. Duplicates are ignored. Default"
                    + " none.")
        List<@NotNull Category> mutedCategories,
    @Schema(
            description =
                "Events of these producers (canonical IDs) are not pushed. Duplicates are"
                    + " ignored; an unknown ID matches no events. At most 100. Default none.")
        @Size(max = PushPreferences.MAX_MUTED_PRODUCERS)
        List<@NotNull UUID> mutedProducerIds) {

  public PushPreferencesRequest {
    // Copies that keep null elements, so validation can report them.
    mutedCategories =
        mutedCategories == null ? null : unmodifiableList(new ArrayList<>(mutedCategories));
    mutedProducerIds =
        mutedProducerIds == null ? null : unmodifiableList(new ArrayList<>(mutedProducerIds));
  }

  PushPreferences toPreferences() {
    var defaults = PushPreferences.DEFAULT;
    return new PushPreferences(
        Objects.requireNonNullElse(enabled, defaults.enabled()),
        Objects.requireNonNullElse(minimumSeverity, defaults.minimumSeverity()),
        Objects.requireNonNullElse(mutedCategories, defaults.mutedCategories()),
        Objects.requireNonNullElse(mutedProducerIds, defaults.mutedProducerIds()));
  }
}
