package io.github.rodrigofabreu.signalhub.event;

import com.fasterxml.jackson.databind.annotation.JsonDeserialize;
import com.fasterxml.jackson.databind.node.ObjectNode;
import io.github.rodrigofabreu.signalhub.api.IsoOffsetDateTimeDeserializer;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.time.OffsetDateTime;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/**
 * Body of {@code POST /api/v1/events}: a generic event as a producer submits it. Unknown fields are
 * rejected, so the server-owned {@code id} and {@code createdAt} cannot be supplied.
 */
@Schema(name = "CreateEventRequest", description = "A generic event submitted by a producer.")
public record CreateEventRequest(
    @Schema(
            description =
                "Identifier of the producer, chosen by the producer. Letters, digits and"
                    + " . _ : / -, starting with a letter or digit.",
            examples = "ci/build-runner")
        @NotNull
        @Size(max = 100)
        @Pattern(regexp = IDENTIFIER, message = IDENTIFIER_MESSAGE)
        String source,
    @Schema(
            description =
                "Optional project or context the event belongs to, for example a repository,"
                    + " host or job. Same characters as source.",
            examples = "signalhub")
        @Size(max = 200)
        @Pattern(regexp = IDENTIFIER, message = IDENTIFIER_MESSAGE)
        String context,
    @NotNull Category category,
    @NotNull Severity severity,
    @Schema(
            description = "Short human-readable summary. Must not be blank.",
            examples = "Nightly build failed")
        @NotBlank
        @Size(max = 200)
        @Pattern(regexp = NO_NUL, message = NO_NUL_MESSAGE)
        String title,
    @Schema(
            description = "Optional longer human-readable text.",
            examples = "3 of 412 tests failed on main.")
        @Size(max = 4000)
        @Pattern(regexp = NO_NUL, message = NO_NUL_MESSAGE)
        String message,
    @Schema(
            description =
                "Optional producer-defined JSON object, stored and returned unchanged but never"
                    + " interpreted by SignalHub. At most 16 KiB as compact UTF-8 JSON.")
        @ValidMetadata
        ObjectNode metadata,
    @Schema(
            description =
                "Optional time the underlying occurrence happened, according to the producer."
                    + " ISO-8601 with a UTC offset. Informational only: SignalHub orders and"
                    + " records events by its own createdAt. Truncated to microseconds.",
            examples = "2026-09-25T14:03:00+02:00")
        @JsonDeserialize(using = IsoOffsetDateTimeDeserializer.class)
        @SupportedTimestamp
        OffsetDateTime occurredAt) {

  // ObjectNode is mutable; copy it so the record stays a value.
  public CreateEventRequest {
    metadata = metadata == null ? null : metadata.deepCopy();
  }

  @Override
  public ObjectNode metadata() {
    return metadata == null ? null : metadata.deepCopy();
  }

  static final String IDENTIFIER = "[A-Za-z0-9][A-Za-z0-9._:/-]*";
  static final String IDENTIFIER_MESSAGE =
      "must start with a letter or digit and contain only letters, digits and . _ : / -";
  static final String NO_NUL = "[^\\x00]*";
  static final String NO_NUL_MESSAGE = "must not contain NUL (U+0000) characters";
}
