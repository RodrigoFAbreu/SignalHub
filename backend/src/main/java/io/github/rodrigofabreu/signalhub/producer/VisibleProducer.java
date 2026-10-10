package io.github.rodrigofabreu.signalhub.producer;

import io.github.rodrigofabreu.signalhub.user.NamedUser;
import java.util.List;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** A producer a user can see, to subscribe to or unsubscribe from. */
@Schema(
    name = "VisibleProducer",
    description =
        "A producer the caller sees: it is public, they own it, or they are on its allow-list."
            + " Nothing of its keys, allow-list or activity.")
public record VisibleProducer(
    @Schema(required = true, description = "Canonical producer ID.") UUID id,
    @Schema(required = true, examples = "ci-build-runner") String name,
    @Schema(required = true, description = "The user who owns the producer.") NamedUser owner,
    @Schema(required = true) Visibility visibility,
    @Schema(required = true, description = "Whether the producer is disabled and publishes none.")
        boolean disabled,
    @Schema(required = true, description = "Whether the caller receives this producer's events.")
        boolean subscribed) {

  /** The producers the caller sees, by name. */
  @Schema(name = "VisibleProducerList", description = "The producers the caller sees, by name.")
  public record Items(
      @Schema(required = true, description = "The producers, by name.")
          List<VisibleProducer> items) {

    public Items {
      items = List.copyOf(items);
    }
  }
}
