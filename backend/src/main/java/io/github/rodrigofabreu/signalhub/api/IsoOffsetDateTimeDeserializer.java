package io.github.rodrigofabreu.signalhub.api;

import com.fasterxml.jackson.core.JsonParser;
import com.fasterxml.jackson.core.JsonToken;
import com.fasterxml.jackson.databind.DeserializationContext;
import com.fasterxml.jackson.databind.deser.std.StdScalarDeserializer;
import java.io.IOException;
import java.time.OffsetDateTime;
import java.time.format.DateTimeParseException;

/**
 * Accepts only ISO-8601 strings with an explicit offset, e.g. {@code 2026-09-25T12:03:00Z}.
 * Jackson's default also accepts epoch numbers, which leave the time zone implicit.
 */
public final class IsoOffsetDateTimeDeserializer extends StdScalarDeserializer<OffsetDateTime> {

  private static final long serialVersionUID = 1L;

  public IsoOffsetDateTimeDeserializer() {
    super(OffsetDateTime.class);
  }

  @Override
  public OffsetDateTime deserialize(JsonParser parser, DeserializationContext context)
      throws IOException {
    if (!parser.hasToken(JsonToken.VALUE_STRING)) {
      return (OffsetDateTime) context.handleUnexpectedToken(OffsetDateTime.class, parser);
    }
    String text = parser.getText();
    try {
      return OffsetDateTime.parse(text);
    } catch (DateTimeParseException e) {
      return (OffsetDateTime)
          context.handleWeirdStringValue(OffsetDateTime.class, text, "not ISO-8601 with offset");
    }
  }
}
