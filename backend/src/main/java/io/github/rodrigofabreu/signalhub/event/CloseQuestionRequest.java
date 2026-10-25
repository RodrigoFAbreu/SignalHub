package io.github.rodrigofabreu.signalhub.event;

import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** Optional body of {@code POST /api/v1/events/{id}/answer/close}. */
@Schema(name = "CloseQuestionRequest", description = "Why the producer closes the question.")
public record CloseQuestionRequest(
    @Schema(
            description =
                "A short note shown with the close, such as where it was answered: 1 to 200"
                    + " characters, not blank.",
            examples = "Answered in the session",
            maxLength = 200)
        @Size(min = 1, max = 200)
        @Pattern(regexp = "(?s).*\\S.*", message = "must not be blank")
        @Pattern(regexp = CreateEventRequest.NO_NUL, message = CreateEventRequest.NO_NUL_MESSAGE)
        String note) {}
