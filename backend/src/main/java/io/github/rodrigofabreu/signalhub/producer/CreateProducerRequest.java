package io.github.rodrigofabreu.signalhub.producer;

import io.github.rodrigofabreu.signalhub.api.Identifiers;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** Body of {@code POST /api/v1/admin/producers}. */
@Schema(name = "CreateProducerRequest", description = "A producer to register.")
public record CreateProducerRequest(
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
                "The user who owns the producer, who is subscribed to it from the start. Optional;"
                    + " the oldest admin who is not revoked when omitted or null.",
            examples = "01997d5e-8a3c-7b1e-9f2a-4c6d8e0f1a2b")
        UUID ownerId,
    @Schema(
            description =
                "PUBLIC or PRIVATE. Optional; PRIVATE when omitted or null: only the owner sees"
                    + " it.")
        Visibility visibility) {

  Visibility visibilityOrDefault() {
    return visibility == null ? Visibility.PRIVATE : visibility;
  }
}
