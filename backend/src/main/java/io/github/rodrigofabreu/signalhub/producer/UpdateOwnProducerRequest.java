package io.github.rodrigofabreu.signalhub.producer;

import io.github.rodrigofabreu.signalhub.api.Identifiers;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** Body of {@code PATCH /api/v1/client/producers/{id}}: each field present is changed. */
@Schema(
    name = "UpdateOwnProducerRequest",
    description =
        "What to change on an own producer: its name, its visibility, or both. A field that is"
            + " omitted or null stays as it is; at least one must be given.")
public record UpdateOwnProducerRequest(
    @Schema(
            description =
                "The new name, as when registering. Its keys keep working and its events keep"
                    + " their producer; they show the new name.",
            examples = "ci-build-runner")
        @Size(max = 100)
        @Pattern(regexp = Identifiers.PATTERN, message = Identifiers.MESSAGE)
        String name,
    @Schema(
            description =
                "PUBLIC: every user may see the producer and subscribe. PRIVATE: only its owner"
                    + " and the users on the allow-list. Making a producer private ends the"
                    + " subscriptions of the users who then no longer see it.")
        Visibility visibility) {

  boolean changesNothing() {
    return name == null && visibility == null;
  }
}
