package io.github.rodrigofabreu.signalhub.api;

import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/**
 * Where a question stands: open, answered, or closed. The body of the producer's read of the answer
 * and of the producer's close, and the {@code question} of a {@code 409} that refuses to answer or
 * close one. {@code CLOSED} by {@code TIME} is derived as soon as {@code closesAt} passes.
 */
@Schema(name = "QuestionState", description = "Where the question of an event stands.")
public record QuestionState(
    @Schema(required = true, description = "OPEN until it is answered or closed.") State state,
    @Schema(description = "The accepted answer; null unless the state is ANSWERED.") Answer answer,
    @Schema(
            description =
                "Who closed it: PRODUCER, or TIME once its closesAt passed. Null unless the state"
                    + " is CLOSED.")
        ClosedBy closedBy,
    @Schema(
            description =
                "When it closed: its closesAt for TIME, the time of the close for PRODUCER. Null"
                    + " unless the state is CLOSED.")
        Instant closedAt,
    @Schema(description = "The producer's note on closing it, if it gave one.") String closeNote) {

  public enum State {
    OPEN,
    ANSWERED,
    CLOSED
  }

  public enum ClosedBy {
    PRODUCER,
    TIME
  }

  /** Where an answer was given. */
  public enum Via {
    APP,
    WEB
  }

  /** The state of a question nobody has answered or closed. */
  public static QuestionState open() {
    return new QuestionState(State.OPEN, null, null, null, null);
  }

  public static QuestionState answered(Answer answer) {
    return new QuestionState(State.ANSWERED, answer, null, null, null);
  }

  public static QuestionState closed(ClosedBy by, Instant at, String note) {
    return new QuestionState(State.CLOSED, null, by, at, note);
  }

  @Schema(name = "QuestionAnswer", description = "The answer a person gave.")
  public record Answer(
      @Schema(
              required = true,
              description =
                  "The ids of the chosen choices, in the question's order; empty for a typed"
                      + " question or an Other answer.")
          List<String> choices,
      @Schema(description = "The typed text; null when there is none.") String text,
      @Schema(required = true, description = "Who answered, by the name they had then.") By by,
      @Schema(required = true, description = "Where it was given.") Via via,
      @Schema(required = true, examples = "2026-10-16T19:02:11Z") Instant at) {

    public Answer {
      choices = List.copyOf(choices);
    }
  }

  @Schema(name = "QuestionAnswerer", description = "The user who answered.")
  public record By(
      @Schema(required = true, description = "Canonical user ID.") UUID id,
      @Schema(required = true, examples = "Anna") String name) {}
}
