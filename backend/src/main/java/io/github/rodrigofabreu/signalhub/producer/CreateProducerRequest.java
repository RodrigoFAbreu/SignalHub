package io.github.rodrigofabreu.signalhub.producer;

import io.github.rodrigofabreu.signalhub.api.Identifiers;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
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
        String name) {}
