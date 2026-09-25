package io.github.rodrigofabreu.signalhub.push;

import io.github.rodrigofabreu.signalhub.event.Category;
import io.github.rodrigofabreu.signalhub.event.Severity;
import java.util.UUID;

/**
 * The provider-neutral content of a push about one stored event. A push is a signal to look, not
 * the record: clients fetch the event by {@code eventId}. Providers decide how to map this onto
 * their own payload.
 */
public record PushMessage(
    UUID eventId, Category category, Severity severity, String title, String message) {}
