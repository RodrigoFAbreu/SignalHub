package io.github.rodrigofabreu.signalhub.event;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.transaction.Transactional;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Optional;
import java.util.UUID;

/** Stores and loads events, and maps between the API models and the persistence entity. */
@ApplicationScoped
class EventService {

  private final EventRepository repository;

  EventService(EventRepository repository) {
    this.repository = repository;
  }

  /** Persists the event and commits before returning, so a returned event is durable. */
  @Transactional
  EventResponse create(CreateEventRequest request) {
    var metadata = request.metadata();
    var event =
        new EventEntity(
            request.source(),
            request.context(),
            request.category(),
            request.severity(),
            request.title(),
            request.message(),
            metadata == null ? "{}" : metadata.toString(),
            request.occurredAt() == null ? null : toStoredInstant(request.occurredAt().toInstant()),
            toStoredInstant(Instant.now()));
    repository.persist(event);
    return toResponse(event);
  }

  @Transactional
  Optional<EventResponse> find(UUID id) {
    return repository.findByIdOptional(id).map(EventService::toResponse);
  }

  // PostgreSQL stores microseconds. Truncating first makes the create response equal later reads.
  private static Instant toStoredInstant(Instant instant) {
    return instant.truncatedTo(ChronoUnit.MICROS);
  }

  private static EventResponse toResponse(EventEntity event) {
    return new EventResponse(
        event.id(),
        event.source(),
        event.context(),
        event.category(),
        event.severity(),
        event.title(),
        event.message(),
        event.metadata(),
        event.occurredAt(),
        event.createdAt());
  }
}
