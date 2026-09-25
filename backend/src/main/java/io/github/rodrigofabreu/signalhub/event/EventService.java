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
  private final PushDispatches dispatches;

  EventService(EventRepository repository, ProducerService producers, PushDispatches dispatches) {
    this.repository = repository;
    this.producers = producers;
    this.dispatches = dispatches;
  }

  /**
   * Persists the event, bound to the authenticated producer, and commits before returning, so a
   * returned event is durable. Its push is recorded in the same transaction and sent later by
   * {@link EventPushDispatcher}.
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
    dispatches.add(event);
    return toResponse(event, producer);
  }

  /** The push for the event; empty if the event no longer exists. */
  @Transactional
  Optional<EventPush> pushFor(UUID id) {
    return repository.findByIdOptional(id).map(EventPush::of);
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

  /** Marks the event read; the event, or empty if it does not exist. */
  @Transactional
  Optional<EventResponse> markRead(UUID id) {
    return repository.markRead(id, toStoredInstant(Instant.now())) ? find(id) : Optional.empty();
  }

  /** Marks the event unread; the event, or empty if it does not exist. */
  @Transactional
  Optional<EventResponse> markUnread(UUID id) {
    return repository.markUnread(id) ? find(id) : Optional.empty();
  }

  /**
   * Marks read every unread event up to the given one in listing order. The count of events marked,
   * or empty if the given event does not exist.
   */
  @Transactional
  Optional<MarkReadResult> markReadThrough(UUID id) {
    return repository
        .findByIdOptional(id)
        .map(
            through ->
                new MarkReadResult(
                    repository.markReadThrough(through, toStoredInstant(Instant.now()))));
  }

  @Transactional
  UnreadCount countUnread() {
    return new UnreadCount(repository.countUnread());
  }

  /**
   * Deletes up to {@code limit} of the oldest events created before {@code cutoff}, in their own
   * transaction; returns how many. Their pending pushes and retries go with them.
   */
  @Transactional
  int deleteCreatedBefore(Instant cutoff, int limit) {
    return repository.deleteCreatedBefore(cutoff, limit);
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
        event.createdAt(),
        event.readAt());
  }
}
