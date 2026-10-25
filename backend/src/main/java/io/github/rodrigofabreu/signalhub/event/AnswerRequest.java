package io.github.rodrigofabreu.signalhub.event;

import io.github.rodrigofabreu.signalhub.api.ApiError;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Objects;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/**
 * Body of {@code PUT /api/v1/events/{id}/answer}. What it may hold depends on the question, so it
 * is checked against the question's rules ({@link #problems}) and not by annotations. An absent
 * {@code choices} is the same as an empty one, and an absent {@code text} as a null one.
 */
@Schema(
    name = "AnswerRequest",
    description = "An answer to the question of an event: the chosen choices and/or typed text.")
public record AnswerRequest(
    @Schema(
            description =
                "The ids of the chosen choices: exactly one for a single-choice question, one or"
                    + " more for a multiple one; none for a typed question or an Other answer.")
        List<String> choices,
    @Schema(
            description =
                "Typed text, 1 to 3000 characters, not blank: a note with the choice, the Other"
                    + " answer, or the whole answer of a typed question, as the question says.")
        String text) {

  public AnswerRequest {
    choices = choices == null ? null : Collections.unmodifiableList(new ArrayList<>(choices));
  }

  /** The chosen ids, never null. */
  List<String> chosen() {
    return choices == null ? List.of() : choices;
  }

  /** The chosen ids in the question's order, once {@link #problems} found none. */
  List<String> inOrderOf(AskView ask) {
    var chosen = new HashSet<>(chosen());
    return ask.choices().stream().map(AskView.Choice::id).filter(chosen::contains).toList();
  }

  /** Whether the other body picks the same choices and says the same text. */
  boolean sameAs(List<String> otherChoices, String otherText) {
    return new HashSet<>(chosen()).equals(new HashSet<>(otherChoices))
        && Objects.equals(text, otherText);
  }

  /** What is wrong with this answer to the question, as violations; empty if it is valid. */
  List<ApiError.Violation> problems(AskView ask) {
    var problems = new ArrayList<ApiError.Violation>();
    var known = new HashSet<String>();
    ask.choices().forEach(c -> known.add(c.id()));
    var seen = new HashSet<String>();
    for (var id : chosen()) {
      if (id == null || !known.contains(id)) {
        problems.add(new ApiError.Violation("choices", "contains a choice the question lacks"));
        break;
      }
      if (!seen.add(id)) {
        problems.add(new ApiError.Violation("choices", "repeats a choice"));
        break;
      }
    }
    var hasText = text != null;
    if (hasText) {
      var length = text.codePointCount(0, text.length());
      if (text.isBlank() || length > Ask.MAX_ANSWER_TEXT || text.indexOf('\0') >= 0) {
        problems.add(
            new ApiError.Violation(
                "text",
                "must be 1 to "
                    + Ask.MAX_ANSWER_TEXT
                    + " characters, not blank, without NUL (U+0000) characters"));
        hasText = false;
      }
    }
    if (problems.isEmpty()) {
      checkShape(ask, chosen().size(), hasText, problems);
    }
    return problems;
  }

  private void checkShape(
      AskView ask, int picked, boolean hasText, ArrayList<ApiError.Violation> problems) {
    if (text != null && !hasText) {
      return;
    }
    var typedOnly = ask.choices().isEmpty();
    if (typedOnly) {
      if (picked > 0) {
        problems.add(new ApiError.Violation("choices", "must be empty: the question has none"));
      }
      if (!hasText) {
        problems.add(new ApiError.Violation("text", "is required"));
      }
      return;
    }
    if (ask.textStyle() == TextStyle.OTHER) {
      checkOther(ask, picked, hasText, problems);
      return;
    }
    checkPicked(ask, picked, problems);
    switch (ask.text()) {
      case NONE -> {
        if (hasText) {
          problems.add(new ApiError.Violation("text", "is not allowed: the question takes none"));
        }
      }
      case REQUIRED -> {
        if (!hasText) {
          problems.add(new ApiError.Violation("text", "is required"));
        }
      }
      case OPTIONAL -> {
        // Either way is valid.
      }
    }
  }

  private static void checkPicked(AskView ask, int picked, ArrayList<ApiError.Violation> problems) {
    if (ask.multiple() ? picked < 1 : picked != 1) {
      problems.add(
          new ApiError.Violation(
              "choices",
              ask.multiple() ? "must have at least one choice" : "must have one choice"));
    }
  }

  /** An Other row takes the place of a choice (single) or may be ticked with them (multiple). */
  private static void checkOther(
      AskView ask, int picked, boolean hasText, ArrayList<ApiError.Violation> problems) {
    if (ask.multiple()) {
      if (picked < 1 && !hasText) {
        problems.add(
            new ApiError.Violation("choices", "must have at least one choice, or text for Other"));
      }
    } else if (picked > 1) {
      problems.add(new ApiError.Violation("choices", "must have at most one choice"));
    } else if (picked == 1 && hasText) {
      problems.add(
          new ApiError.Violation("text", "is not allowed with a choice: it is the Other answer"));
    } else if (picked == 0 && !hasText) {
      problems.add(new ApiError.Violation("choices", "must have one choice, or text for Other"));
    }
  }
}
