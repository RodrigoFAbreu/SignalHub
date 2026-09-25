package io.github.rodrigofabreu.signalhub.event;

import static java.lang.annotation.ElementType.FIELD;
import static java.lang.annotation.ElementType.PARAMETER;
import static java.lang.annotation.ElementType.RECORD_COMPONENT;
import static java.lang.annotation.RetentionPolicy.RUNTIME;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import jakarta.validation.Constraint;
import jakarta.validation.ConstraintValidator;
import jakarta.validation.ConstraintValidatorContext;
import jakarta.validation.Payload;
import java.lang.annotation.Retention;
import java.lang.annotation.Target;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.util.Map;

/**
 * Producer metadata must be small and storable in PostgreSQL {@code jsonb}. The contents are never
 * interpreted: these are storage limits, not producer rules. A null value is valid.
 */
@Target({FIELD, PARAMETER, RECORD_COMPONENT})
@Retention(RUNTIME)
@Constraint(validatedBy = ValidMetadata.Validator.class)
@interface ValidMetadata {

  /** Upper bound on the compact UTF-8 JSON encoding, so events stay cheap to store and push. */
  int MAX_BYTES = 16 * 1024;

  String message() default "";

  Class<?>[] groups() default {};

  Class<? extends Payload>[] payload() default {};

  class Validator implements ConstraintValidator<ValidMetadata, ObjectNode> {

    // PostgreSQL numeric limits: digits before and after the decimal point.
    private static final int MAX_INTEGER_DIGITS = 131_072;
    private static final int MAX_FRACTION_DIGITS = 16_383;

    @Override
    public boolean isValid(ObjectNode metadata, ConstraintValidatorContext context) {
      if (metadata == null) {
        return true;
      }
      String problem = problemWith(metadata);
      if (problem == null) {
        return true;
      }
      context.disableDefaultConstraintViolation();
      context.buildConstraintViolationWithTemplate(problem).addConstraintViolation();
      return false;
    }

    private static String problemWith(ObjectNode metadata) {
      if (metadata.toString().getBytes(StandardCharsets.UTF_8).length > MAX_BYTES) {
        return "must be at most " + MAX_BYTES + " bytes when encoded as compact UTF-8 JSON";
      }
      if (!storable(metadata)) {
        // PostgreSQL rejects both in jsonb.
        return "must not contain NUL (U+0000) characters or numbers outside the PostgreSQL"
            + " numeric range";
      }
      return null;
    }

    private static boolean storable(JsonNode node) {
      if (node.isTextual()) {
        return hasNoNul(node.textValue());
      }
      if (node.isNumber()) {
        return fitsNumeric(node.decimalValue());
      }
      if (node.isObject()) {
        for (Map.Entry<String, JsonNode> field : node.properties()) {
          if (!hasNoNul(field.getKey()) || !storable(field.getValue())) {
            return false;
          }
        }
        return true;
      }
      for (JsonNode element : node) {
        if (!storable(element)) {
          return false;
        }
      }
      return true;
    }

    private static boolean hasNoNul(String text) {
      return text.indexOf('\0') < 0;
    }

    private static boolean fitsNumeric(BigDecimal number) {
      return number.precision() - number.scale() <= MAX_INTEGER_DIGITS
          && number.scale() <= MAX_FRACTION_DIGITS;
    }
  }
}
