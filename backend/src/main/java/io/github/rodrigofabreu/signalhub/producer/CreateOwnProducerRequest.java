package io.github.rodrigofabreu.signalhub.producer;

import io.github.rodrigofabreu.signalhub.api.Identifiers;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** Body of {@code POST /api/v1/client/producers}. The owner is always the caller's user. */
@Schema(name = "CreateOwnProducerRequest", description = "A producer to register for the caller.")
public record CreateOwnProducerRequest(
    @Schema(
            description =
                "Unique, stable machine-readable name, shown on the producer's events. Letters,"
                    + " digits and . _ : / -, starting with a letter or digit.",
            examples = "ci-build-runner")
        @NotNull
        @Size(max = 100)
        @Pattern(regexp = Identifiers.PATTERN, message = Identifiers.MESSAGE)
        String name,
    @Schema(
            description =
                "PUBLIC or PRIVATE. Optional; PRIVATE when omitted or null: only the owner sees"
                    + " it.")
        Visibility visibility) {

  Visibility visibilityOrDefault() {
    return visibility == null ? Visibility.PRIVATE : visibility;
  }
}
