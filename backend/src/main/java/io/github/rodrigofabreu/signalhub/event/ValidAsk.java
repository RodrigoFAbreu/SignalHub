package io.github.rodrigofabreu.signalhub.event;

import static java.lang.annotation.ElementType.FIELD;
import static java.lang.annotation.ElementType.PARAMETER;
import static java.lang.annotation.ElementType.RECORD_COMPONENT;
import static java.lang.annotation.RetentionPolicy.RUNTIME;

import io.github.rodrigofabreu.signalhub.api.Identifiers;
import jakarta.validation.Constraint;
import jakarta.validation.ConstraintValidator;
import jakarta.validation.ConstraintValidatorContext;
import jakarta.validation.Payload;
import java.lang.annotation.Retention;
import java.lang.annotation.Target;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.regex.Pattern;

/**
 * An event's question must be well formed on its own: how many choices, what they are called, and
 * which kinds of text go with which style. That it closes in the future, at most {@link
 * EventService#MAX_ASK_DURATION} ahead, is checked by the service after the idempotency lookup, so
 * a retry of a published question is not refused once its time has passed. Each problem names its
 * field under {@code ask}. A null question is valid.
 */
@Target({FIELD, PARAMETER, RECORD_COMPONENT})
@Retention(RUNTIME)
@Constraint(validatedBy = ValidAsk.Validator.class)
@interface ValidAsk {

  String message() default "is not a valid question";

  Class<?>[] groups() default {};

  Class<? extends Payload>[] payload() default {};

  class Validator implements ConstraintValidator<ValidAsk, Ask> {

    private static final Pattern ID = Pattern.compile(Identifiers.PATTERN);
    private static final int MAX_ID = 64;

    /** A problem with the field at {@code path} below {@code ask}. */
    record Problem(String path, String message) {}

    @Override
    public boolean isValid(Ask ask, ConstraintValidatorContext context) {
      if (ask == null) {
        return true;
      }
      var problems = problems(ask);
      if (problems.isEmpty()) {
        return true;
      }
      context.disableDefaultConstraintViolation();
      for (var problem : problems) {
        var builder = context.buildConstraintViolationWithTemplate(problem.message());
        var node = builder.addPropertyNode(problem.path().split("\\.")[0]);
        var rest = problem.path().split("\\.");
        for (var i = 1; i < rest.length; i++) {
          node = node.addPropertyNode(rest[i]);
        }
        node.addConstraintViolation();
      }
      return false;
    }

    static List<Problem> problems(Ask ask) {
      var problems = new ArrayList<Problem>();
      var choices = ask.choices() == null ? List.<Ask.Choice>of() : ask.choices();
      checkChoices(choices, ask.textStyle(), problems);
      if (ask.multiple() != null && ask.multiple() && choices.size() < 2) {
        problems.add(new Problem("multiple", "needs at least 2 choices"));
      }
      checkText(ask, choices, problems);
      if (ask.closesAt() != null
          && (ask.closesAt().getYear() < 1 || ask.closesAt().getYear() > 9999)) {
        problems.add(new Problem("closesAt", "year must be between 0001 and 9999"));
      }
      return problems;
    }

    private static void checkChoices(
        List<Ask.Choice> choices, TextStyle style, List<Problem> problems) {
      if (choices.size() > Ask.MAX_CHOICES) {
        problems.add(new Problem("choices", "must have at most " + Ask.MAX_CHOICES + " items"));
      }
      var ids = new HashSet<String>();
      var labels = new HashSet<String>();
      for (var i = 0; i < choices.size(); i++) {
        var choice = choices.get(i);
        var at = "choices[" + i + "]";
        if (choice == null) {
          problems.add(new Problem(at, "must not be null"));
          continue;
        }
        checkId(choice.id(), at + ".id", ids, problems);
        checkLabel(choice.label(), at + ".label", labels, style, problems);
        var description = choice.description();
        if (description != null
            && (description.length() > Ask.MAX_DESCRIPTION || description.indexOf('\0') >= 0)) {
          problems.add(
              new Problem(
                  at + ".description",
                  "must be at most "
                      + Ask.MAX_DESCRIPTION
                      + " characters and must not contain NUL (U+0000) characters"));
        }
      }
    }

    private static void checkId(String id, String path, HashSet<String> seen, List<Problem> out) {
      if (id == null) {
        out.add(new Problem(path, "must not be null"));
      } else if (id.length() > MAX_ID || !ID.matcher(id).matches()) {
        out.add(
            new Problem(path, "must be at most " + MAX_ID + " characters: " + Identifiers.MESSAGE));
      } else if (!seen.add(id)) {
        out.add(new Problem(path, "must be unique in the question"));
      }
    }

    private static void checkLabel(
        String label, String path, HashSet<String> seen, TextStyle style, List<Problem> out) {
      if (label == null) {
        out.add(new Problem(path, "must not be null"));
        return;
      }
      var length = label.codePointCount(0, label.length());
      if (length < 1 || length > Ask.MAX_LABEL || label.isBlank()) {
        out.add(new Problem(path, "must be 1 to " + Ask.MAX_LABEL + " characters, not blank"));
      } else if (label.codePoints().anyMatch(Character::isISOControl)) {
        out.add(new Problem(path, "must not contain control characters or line breaks"));
      } else if (!seen.add(label.toLowerCase(Locale.ROOT))) {
        out.add(new Problem(path, "must be unique in the question, ignoring case"));
      } else if (style == TextStyle.OTHER && label.strip().equalsIgnoreCase("other")) {
        out.add(
            new Problem(path, "must not be \"Other\" when textStyle is OTHER: that row is added"));
      }
    }

    private static void checkText(Ask ask, List<Ask.Choice> choices, List<Problem> problems) {
      var text = ask.text();
      if (choices.isEmpty() && text != null && text != AskText.REQUIRED) {
        problems.add(new Problem("text", "must be REQUIRED when the question has no choices"));
      }
      if (text == null && !choices.isEmpty()) {
        text = AskText.NONE;
      }
      if (ask.textStyle() != null) {
        if (choices.isEmpty()) {
          problems.add(new Problem("textStyle", "needs choices"));
        } else if (text == AskText.NONE) {
          problems.add(new Problem("textStyle", "needs text OPTIONAL or REQUIRED"));
        } else if (ask.textStyle() == TextStyle.OTHER && text == AskText.REQUIRED) {
          problems.add(new Problem("textStyle", "OTHER needs text OPTIONAL"));
        }
      }
    }
  }
}
