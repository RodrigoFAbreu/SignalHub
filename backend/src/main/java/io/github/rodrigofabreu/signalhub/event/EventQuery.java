package io.github.rodrigofabreu.signalhub.event;

import io.github.rodrigofabreu.signalhub.api.ApiError;
import jakarta.ws.rs.BadRequestException;
import jakarta.ws.rs.core.Response;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.EnumSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

/**
 * A validated event listing request. Values within one filter are alternatives; different filters
 * must all match. Empty sets and absent bounds mean "no restriction".
 *
 * @param createdFrom inclusive lower bound on {@code createdAt}
 * @param createdBefore exclusive upper bound on {@code createdAt}
 * @param after position to continue after, from a previous page's cursor
 */
record EventQuery(
    Set<UUID> producerIds,
    Set<Category> categories,
    Set<Severity> severities,
    Optional<Instant> createdFrom,
    Optional<Instant> createdBefore,
    Optional<EventCursor> after,
    int limit) {

  static final int DEFAULT_LIMIT = 50;
  static final int MAX_LIMIT = 100;

  EventQuery {
    producerIds = Set.copyOf(producerIds);
    categories = Set.copyOf(categories);
    severities = Set.copyOf(severities);
  }

  /**
   * Parses raw query parameters. Parsing is done here rather than by JAX-RS, which answers an
   * unparseable query parameter with a bare 404; every problem is reported as a 400 naming the
   * parameter instead.
   */
  static EventQuery parse(
      List<String> producerIds,
      List<String> categories,
      List<String> severities,
      String createdFrom,
      String createdBefore,
      String cursor,
      String limit) {
    var problems = new ArrayList<ApiError.Violation>();
    var query =
        new EventQuery(
            parseAll("producerId", producerIds, EventQuery::parseUuid, problems),
            parseEnums("category", categories, Category.class, problems),
            parseEnums("severity", severities, Severity.class, problems),
            parseTimestamp("createdFrom", createdFrom, problems),
            parseTimestamp("createdBefore", createdBefore, problems),
            parseCursor(cursor, problems),
            parseLimit(limit, problems));
    if (!problems.isEmpty()) {
      problems.sort(
          Comparator.comparing(ApiError.Violation::field)
              .thenComparing(ApiError.Violation::message));
      throw new BadRequestException(
          Response.status(Response.Status.BAD_REQUEST)
              .entity(new ApiError("Invalid request", 400, problems))
              .build());
    }
    return query;
  }

  private interface Parser<T> {
    /** The parsed value, or null if the text is invalid. */
    T parse(String text);
  }

  private static <T> Set<T> parseAll(
      String field, List<String> values, Parser<T> parser, List<ApiError.Violation> problems) {
    var parsed = new LinkedHashSet<T>();
    for (var text : values == null ? List.<String>of() : values) {
      var value = parser.parse(text);
      if (value == null) {
        problems.add(new ApiError.Violation(field, "is not a valid value: " + text));
      } else {
        parsed.add(value);
      }
    }
    return parsed;
  }

  private static <E extends Enum<E>> Set<E> parseEnums(
      String field, List<String> values, Class<E> type, List<ApiError.Violation> problems) {
    var parsed = EnumSet.noneOf(type);
    var allowed = Arrays.toString(type.getEnumConstants());
    for (var text : values == null ? List.<String>of() : values) {
      try {
        parsed.add(Enum.valueOf(type, text));
      } catch (IllegalArgumentException e) {
        problems.add(new ApiError.Violation(field, "must be one of " + allowed));
      }
    }
    return parsed;
  }

  private static UUID parseUuid(String text) {
    try {
      // UUID.fromString accepts non-canonical forms such as "1-1-1-1-1"; require the canonical one.
      var uuid = UUID.fromString(text);
      return uuid.toString().equalsIgnoreCase(text) ? uuid : null;
    } catch (IllegalArgumentException e) {
      return null;
    }
  }

  private static Optional<Instant> parseTimestamp(
      String field, String text, List<ApiError.Violation> problems) {
    if (text == null) {
      return Optional.empty();
    }
    try {
      var timestamp = OffsetDateTime.parse(text);
      if (timestamp.getYear() >= 1 && timestamp.getYear() <= 9999) {
        return Optional.of(timestamp.toInstant());
      }
    } catch (DateTimeParseException e) {
      // Reported below.
    }
    problems.add(
        new ApiError.Violation(
            field, "must be an ISO-8601 timestamp with a UTC offset, e.g. 2026-09-25T12:03:00Z"));
    return Optional.empty();
  }

  private static Optional<EventCursor> parseCursor(String text, List<ApiError.Violation> problems) {
    if (text == null) {
      return Optional.empty();
    }
    var cursor = EventCursor.decode(text);
    if (cursor.isEmpty()) {
      problems.add(
          new ApiError.Violation("cursor", "must be a nextCursor value returned by this API"));
    }
    return cursor;
  }

  private static int parseLimit(String text, List<ApiError.Violation> problems) {
    if (text == null) {
      return DEFAULT_LIMIT;
    }
    try {
      int limit = Integer.parseInt(text);
      if (limit >= 1 && limit <= MAX_LIMIT) {
        return limit;
      }
    } catch (NumberFormatException e) {
      // Reported below.
    }
    problems.add(new ApiError.Violation("limit", "must be an integer between 1 and " + MAX_LIMIT));
    return DEFAULT_LIMIT;
  }
}
