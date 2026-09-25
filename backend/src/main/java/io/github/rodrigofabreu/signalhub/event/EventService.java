package io.github.rodrigofabreu.signalhub.event;

import static java.util.stream.Collectors.toSet;

import io.github.rodrigofabreu.signalhub.producer.ProducerIdentity;
import io.github.rodrigofabreu.signalhub.producer.ProducerService;
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
  private final ProducerService producers;

  EventService(EventRepository repository, ProducerService producers) {
    this.repository = repository;
    this.producers = producers;
  }

  /**
   * Persists the event, bound to the authenticated producer, and commits before returning, so a
   * returned event is durable.
   */
  @Transactional
  EventResponse create(ProducerIdentity producer, CreateEventRequest request) {
    var metadata = request.metadata();
    var event =
        new EventEntity(
            producer.id(),
            request.context(),
            request.category(),
            request.severity(),
            request.title(),
            request.message(),
            metadata == null ? "{}" : metadata.toString(),
            request.occurredAt() == null ? null : toStoredInstant(request.occurredAt().toInstant()),
            toStoredInstant(Instant.now()));
    repository.persist(event);
    return toResponse(event, producer);
  }

  @Transactional
  Optional<EventResponse> find(UUID id) {
    return repository.findByIdOptional(id).map(event -> toResponse(event, producerOf(event)));
  }

  /**
   * One page of events matching the query, newest first. Reads one row more than the page holds to
   * learn whether another page follows, and loads the page's producers in one query.
   */
  @Transactional
  EventPage list(EventQuery query) {
    var rows = repository.find(query, query.limit() + 1);
    var page = rows.subList(0, Math.min(rows.size(), query.limit()));
    var producersById = producers.find(page.stream().map(EventEntity::producerId).collect(toSet()));
    var items = page.stream().map(e -> toResponse(e, producersById.get(e.producerId()))).toList();
    String nextCursor = null;
    if (rows.size() > page.size()) {
      var last = page.get(page.size() - 1);
      nextCursor = new EventCursor(last.createdAt(), last.id()).encode();
    }
    return new EventPage(items, nextCursor);
  }

  // The foreign key guarantees the producer exists.
  private ProducerIdentity producerOf(EventEntity event) {
    return producers.find(event.producerId()).orElseThrow();
  }

  // PostgreSQL stores microseconds. Truncating first makes the create response equal later reads.
  private static Instant toStoredInstant(Instant instant) {
    return instant.truncatedTo(ChronoUnit.MICROS);
  }

  private static EventResponse toResponse(EventEntity event, ProducerIdentity producer) {
    return new EventResponse(
        event.id(),
        new EventResponse.Producer(producer.id(), producer.name()),
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
