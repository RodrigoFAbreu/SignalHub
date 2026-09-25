package io.github.rodrigofabreu.signalhub.api;

import java.util.List;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** Error body of 400 and 404 responses from the product API. */
@Schema(name = "Error", description = "Why a request was rejected.")
public record ApiError(
    @Schema(required = true, examples = "Invalid request") String title,
    @Schema(required = true, examples = "400") int status,
    @Schema(required = true, description = "Per-field problems; empty when not field-specific.")
        List<Violation> violations) {

  public ApiError {
    violations = List.copyOf(violations);
  }

  @Schema(name = "Violation")
  public record Violation(
      @Schema(
              required = true,
              description = "JSON path of the offending field, or empty for the whole body.",
              examples = "severity")
          String field,
      @Schema(required = true, examples = "must not be null") String message) {}
}
