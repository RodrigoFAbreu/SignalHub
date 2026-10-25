package io.github.rodrigofabreu.signalhub.event;

import com.fasterxml.jackson.databind.annotation.JsonDeserialize;
import io.github.rodrigofabreu.signalhub.api.IsoOffsetDateTimeDeserializer;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/**
 * The optional {@code ask} of {@code POST /api/v1/events}: a question on the event, as a producer
 * sends it. Choices and text are opaque to SignalHub, which stores and shows them and never
 * interprets them. Unknown fields are rejected, so the response-only {@code whoCanAnswer} cannot be
 * sent. {@link ValidAsk} checks it; {@link #normalized} is what is stored and compared.
 */
@Schema(
    name = "Ask",
    description =
        "A question on the event: choices to pick from, typed text, or both. The people allowed"
            + " to answer it (the producer's owner and answerers) do so in their client; the first"
            + " answer wins and ends the question for everyone.")
public record Ask(
    @Schema(
            description = "0 to 10 choices. Without choices the question is typed (text REQUIRED).",
            maxItems = 10)
        List<Choice> choices,
    @Schema(
            description =
                "false (the default): pick one. true: pick one or more; needs at least 2"
                    + " choices.")
        Boolean multiple,
    @Schema(
            description =
                "NONE, OPTIONAL or REQUIRED typed text. Omitted: NONE with choices, REQUIRED"
                    + " without. Without choices it must be REQUIRED. A typed answer is 1 to 3000"
                    + " characters.")
        AskText text,
    @Schema(
            description =
                "Only with choices and text not NONE. NOTE (the default): the text is a note"
                    + " written with the chosen choice. OTHER: an Other row is picked instead of a"
                    + " choice and the text is the answer; needs text OPTIONAL, and no choice"
                    + " labelled Other.")
        TextStyle textStyle,
    @Schema(
            description =
                "Optional time after which nobody can answer: ISO-8601 with a UTC offset, in the"
                    + " future and at most 30 days ahead. Truncated to microseconds.",
            examples = "2026-10-17T09:00:00Z")
        @JsonDeserialize(using = IsoOffsetDateTimeDeserializer.class)
        OffsetDateTime closesAt) {

  // The list is the caller's own; copy it (it may hold a null, which validation reports).
  public Ask {
    choices = choices == null ? null : Collections.unmodifiableList(new ArrayList<>(choices));
  }

  static final int MAX_CHOICES = 10;
  static final int MAX_LABEL = 100;
  static final int MAX_DESCRIPTION = 1000;
  static final int MAX_ANSWER_TEXT = 3000;

  @Schema(name = "AskChoice", description = "One choice of a question.")
  public record Choice(
      @Schema(
              required = true,
              description =
                  "The producer's identifier for the choice, unique in the question: letters,"
                      + " digits and . _ : / -, at most 64 characters. An answer carries it.",
              examples = "merge")
          String id,
      @Schema(
              required = true,
              description =
                  "What the person sees: 1 to 100 characters, no line breaks, unique in the"
                      + " question ignoring case.",
              examples = "Merge")
          String label,
      @Schema(
              description =
                  "Optional text shown under the label: at most 1000 characters. Shown nowhere"
                      + " when absent or empty.",
              examples = "Squash-merge now; CI passed.")
          String description) {}

  /** The question as it is stored: defaults filled in, empty descriptions dropped. */
  AskView normalized() {
    var given = choices == null ? List.<Choice>of() : choices;
    var kept =
        given.stream()
            .map(
                c ->
                    new AskView.Choice(
                        c.id(),
                        c.label(),
                        c.description() == null || c.description().isEmpty()
                            ? null
                            : c.description()))
            .toList();
    var effectiveText = text != null ? text : (kept.isEmpty() ? AskText.REQUIRED : AskText.NONE);
    var effectiveStyle =
        !kept.isEmpty() && effectiveText != AskText.NONE
            ? (textStyle != null ? textStyle : TextStyle.NOTE)
            : null;
    return new AskView(
        kept,
        Boolean.TRUE.equals(multiple),
        effectiveText,
        effectiveStyle,
        closesAt == null
            ? null
            : closesAt.toInstant().truncatedTo(java.time.temporal.ChronoUnit.MICROS),
        null);
  }
}
