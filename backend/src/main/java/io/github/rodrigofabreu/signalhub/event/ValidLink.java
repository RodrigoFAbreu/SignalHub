package io.github.rodrigofabreu.signalhub.event;

import static java.lang.annotation.ElementType.FIELD;
import static java.lang.annotation.ElementType.PARAMETER;
import static java.lang.annotation.ElementType.RECORD_COMPONENT;
import static java.lang.annotation.RetentionPolicy.RUNTIME;

import jakarta.validation.Constraint;
import jakarta.validation.ConstraintValidator;
import jakarta.validation.ConstraintValidatorContext;
import jakarta.validation.Payload;
import java.lang.annotation.Retention;
import java.lang.annotation.Target;
import java.net.URI;
import java.net.URISyntaxException;
import java.util.Locale;
import java.util.Set;

/**
 * An event's link must be an absolute {@code http} or {@code https} URL with a host, so a client
 * can hand it to a browser. Other schemes (such as {@code javascript:} or {@code file:}) could do
 * something else on the owner's device when opened. The URL is only parsed, never fetched. A null
 * value is valid.
 */
@Target({FIELD, PARAMETER, RECORD_COMPONENT})
@Retention(RUNTIME)
@Constraint(validatedBy = ValidLink.Validator.class)
@interface ValidLink {

  /** Long enough for real URLs (browsers and CDNs commonly allow about 2000), short to push. */
  int MAX_LENGTH = 2000;

  String message() default "must be an absolute http or https URL";

  Class<?>[] groups() default {};

  Class<? extends Payload>[] payload() default {};

  class Validator implements ConstraintValidator<ValidLink, String> {

    private static final Set<String> SCHEMES = Set.of("http", "https");

    @Override
    public boolean isValid(String link, ConstraintValidatorContext context) {
      if (link == null) {
        return true;
      }
      try {
        var uri = new URI(link);
        return uri.getScheme() != null
            && SCHEMES.contains(uri.getScheme().toLowerCase(Locale.ROOT))
            && uri.getHost() != null;
      } catch (URISyntaxException e) {
        return false;
      }
    }
  }
}
