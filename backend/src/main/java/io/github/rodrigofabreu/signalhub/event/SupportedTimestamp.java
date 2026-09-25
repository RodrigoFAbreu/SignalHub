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
import java.time.OffsetDateTime;

/**
 * Restricts timestamps to four-digit years. ISO-8601 allows expanded years such as {@code
 * +999999-01-01T00:00:00Z}, which PostgreSQL cannot store. A null value is valid.
 */
@Target({FIELD, PARAMETER, RECORD_COMPONENT})
@Retention(RUNTIME)
@Constraint(validatedBy = SupportedTimestamp.Validator.class)
@interface SupportedTimestamp {

  String message() default "year must be between 0001 and 9999";

  Class<?>[] groups() default {};

  Class<? extends Payload>[] payload() default {};

  class Validator implements ConstraintValidator<SupportedTimestamp, OffsetDateTime> {
    @Override
    public boolean isValid(OffsetDateTime value, ConstraintValidatorContext context) {
      return value == null || (value.getYear() >= 1 && value.getYear() <= 9999);
    }
  }
}
