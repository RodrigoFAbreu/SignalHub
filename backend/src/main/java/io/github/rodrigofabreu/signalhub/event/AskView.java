package io.github.rodrigofabreu.signalhub.event;

import com.fasterxml.jackson.annotation.JsonInclude;
import io.github.rodrigofabreu.signalhub.user.NamedUser;
import java.time.Instant;
import java.util.List;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/**
 * A question as stored and as every event response shows it: normalized, with the defaults filled
 * in. The stored form has no {@code whoCanAnswer}, which is looked up when a response is built.
 */
@Schema(name = "AskView", description = "The question of an event, with its defaults filled in.")
public record AskView(
    @Schema(required = true) List<Choice> choices,
    @Schema(required = true) boolean multiple,
    @Schema(required = true) AskText text,
    @Schema(
            description =
                "NOTE or OTHER when the question has choices and takes text; null otherwise.")
        TextStyle textStyle,
    @Schema(description = "When the question closes by itself; null if it does not.")
        Instant closesAt,
    @Schema(
            description =
                "Who may answer it now, by name: the producer's owner first, then its answerers."
                    + " Revoked users are left out, so it may be empty. Only in event responses.")
        @JsonInclude(JsonInclude.Include.NON_NULL)
        List<NamedUser> whoCanAnswer) {

  public AskView {
    choices = List.copyOf(choices);
    whoCanAnswer = whoCanAnswer == null ? null : List.copyOf(whoCanAnswer);
  }

  AskView withWhoCanAnswer(List<NamedUser> who) {
    return new AskView(choices, multiple, text, textStyle, closesAt, who);
  }

  @Schema(name = "AskViewChoice", description = "One choice of a question.")
  public record Choice(
      @Schema(required = true) String id,
      @Schema(required = true) String label,
      @Schema(description = "Text shown under the label; null when there is none.")
          String description) {}
}
