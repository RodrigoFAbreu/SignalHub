package io.github.rodrigofabreu.signalhub.event;

import static java.util.stream.Collectors.joining;
import static java.util.stream.Collectors.toSet;

import io.github.rodrigofabreu.signalhub.producer.ProducerAccess;
import io.github.rodrigofabreu.signalhub.producer.ProducerIdentity;
import io.github.rodrigofabreu.signalhub.producer.ProducerService;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.transaction.Transactional;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.temporal.ChronoUnit;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Stream;
import org.jboss.logging.Logger;

/** Stores and loads events, and maps between the API models and the persistence entity. */
@ApplicationScoped
class EventService {

  private static final Logger LOG = Logger.getLogger(EventService.class);

  private final EventRepository repository;
  private final ProducerService producers;
  private final PushDispatches dispatches;
  private final ProducerAccess access;
  private final EventReads reads;

  EventService(
      EventRepository repository,
      ProducerService producers,
      PushDispatches dispatches,
      ProducerAccess access,
      EventReads reads) {
    this.repository = repository;
    this.producers = producers;
    this.dispatches = dispatches;
    this.access = access;
    this.reads = reads;
  }

  /** The outcome of publishing: the event, and whether this request stored it. */
  record Published(EventResponse event, boolean created) {}

  /**
   * Persists the event, bound to the authenticated producer, and commits before returning, so a
   * returned event is durable. Its push is recorded in the same transaction and sent later by
   * {@link EventPushDispatcher}. With an idempotency key the producer already used, nothing is
   * stored and the event stored then is returned, if the request is the same.
   *
   * <p>Publishing is serialized, and {@code createdAt} is taken under the lock and kept after every
   * stored event's, so events become visible in listing order: a client that has read an event
   * never later finds an older one it had not seen.
   *
   * @throws IdempotencyKeyReusedException if the key was used for a different event
   */
  @Transactional
  Published create(ProducerIdentity producer, CreateEventRequest request, String idempotencyKey) {
    repository.lockPublishing();
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
            request.link(),
            request.occurredAt() == null ? null : toStoredInstant(request.occurredAt().toInstant()),
            nextCreatedAt(),
            idempotencyKey);
    if (idempotencyKey != null) {
      var stored = repository.findByIdempotencyKey(producer.id(), idempotencyKey);
      if (stored.isPresent()) {
        if (!sameRequest(stored.get(), event)) {
          throw new IdempotencyKeyReusedException();
        }
        return new Published(toResponse(stored.get(), producer, null), false);
      }
    }
    repository.persist(event);
    dispatches.add(event);
    return new Published(toResponse(event, producer, null), true);
  }

  /**
   * Publishes the event as the given producer on the operator's behalf, exactly as that producer's
   * own event without an idempotency key: stored, then pushed through every client's preferences.
   */
  @Transactional
  EventResponse createAsOperator(ProducerIdentity producer, CreateEventRequest request) {
    var event = create(producer, request, null).event();
    LOG.infof("Operator sent event %s as producer %s", event.id(), producer.id());
    return event;
  }

  /**
   * Now, or just after the newest stored event if that is later (same microsecond, or a clock set
   * back), so the listing never orders a new event before one already visible.
   */
  private Instant nextCreatedAt() {
    var now = toStoredInstant(Instant.now());
    return repository
        .latestCreatedAt()
        .map(latest -> latest.plus(1, ChronoUnit.MICROS))
        .filter(next -> next.isAfter(now))
        .orElse(now);
  }

  /** Whether the stored event holds what {@code sent} would have stored, its own fields aside. */
  private boolean sameRequest(EventEntity stored, EventEntity sent) {
    return Objects.equals(stored.context(), sent.context())
        && stored.category() == sent.category()
        && stored.severity() == sent.severity()
        && stored.title().equals(sent.title())
        && Objects.equals(stored.message(), sent.message())
        && Objects.equals(stored.link(), sent.link())
        && Objects.equals(stored.occurredAt(), sent.occurredAt())
        && repository.sameMetadata(stored.metadata(), sent.metadata());
  }

  /** The push for the event; empty if the event no longer exists. */
  @Transactional
  Optional<EventPush> pushFor(UUID id) {
    return repository.findByIdOptional(id).map(EventPush::of);
  }

  /**
   * The event, if it exists and the user receives it: the operator ({@code user} empty) sees every
   * event with their own read state, a user only the events of the producers they are subscribed
   * to, with their read state. Any other event is empty, whether it exists or not.
   */
  @Transactional
  Optional<EventResponse> find(UUID id, Optional<UUID> user) {
    return repository
        .findByIdOptional(id)
        .filter(event -> receivedBy(event, user))
        .map(
            event ->
                toResponse(
                    event,
                    producerOf(event),
                    user.isPresent()
                        ? reads.readAt(user.get(), List.of(id)).get(id)
                        : event.readAt()));
  }

  private boolean receivedBy(EventEntity event, Optional<UUID> user) {
    return user.isEmpty() || access.subscribedProducerIds(user.get()).contains(event.producerId());
  }

  /**
   * One page of the events the user receives (every event for the operator, who is no user),
   * matching the query, newest first. Reads one row more than the page holds to learn whether
   * another page follows, and loads the page's producers in one query.
   */
  @Transactional
  EventPage list(EventQuery query, Optional<UUID> user) {
    var viewer = user.map(u -> new EventRepository.Viewer(u, access.subscribedProducerIds(u)));
    var rows = repository.find(query, query.limit() + 1, viewer, userProducers(query));
    var page = rows.subList(0, Math.min(rows.size(), query.limit()));
    var producersById = producers.find(page.stream().map(EventEntity::producerId).collect(toSet()));
    var readAt =
        user.map(u -> reads.readAt(u, page.stream().map(EventEntity::id).toList()))
            .orElse(Map.of());
    var items =
        page.stream()
            .map(
                e ->
                    toResponse(
                        e,
                        producersById.get(e.producerId()),
                        user.isPresent() ? readAt.get(e.id()) : e.readAt()))
            .toList();
    String nextCursor = null;
    if (rows.size() > page.size()) {
      var last = page.get(page.size() - 1);
      nextCursor = new EventCursor(last.createdAt(), last.id()).encode();
    }
    return new EventPage(items, nextCursor);
  }

  /**
   * The producers the query's user owns and/or is subscribed to, as its relation says; empty (no
   * restriction) if the query names no user.
   */
  Optional<Set<UUID>> userProducers(EventQuery query) {
    return query
        .userId()
        .map(
            id -> {
              var producerIds = new HashSet<UUID>();
              if (query.relation().isEmpty() || query.relation().get() == UserRelation.OWNED) {
                producerIds.addAll(access.ownedProducerIds(id));
              }
              if (query.relation().isEmpty() || query.relation().get() == UserRelation.SUBSCRIBED) {
                producerIds.addAll(access.subscribedProducerIds(id));
              }
              return producerIds;
            });
  }

  /** Marks the event read; the event, or empty if it does not exist or the user lacks it. */
  @Transactional
  Optional<EventResponse> markRead(UUID id, Optional<UUID> user) {
    if (user.isPresent()) {
      if (find(id, user).isEmpty()) {
        return Optional.empty();
      }
      reads.markRead(user.get(), id, toStoredInstant(Instant.now()));
      return find(id, user);
    }
    return repository.markRead(id, toStoredInstant(Instant.now()))
        ? find(id, user)
        : Optional.empty();
  }

  /** Marks the event unread; the event, or empty if it does not exist or the user lacks it. */
  @Transactional
  Optional<EventResponse> markUnread(UUID id, Optional<UUID> user) {
    if (user.isPresent()) {
      if (find(id, user).isEmpty()) {
        return Optional.empty();
      }
      reads.markUnread(user.get(), id);
      return find(id, user);
    }
    return repository.markUnread(id) ? find(id, user) : Optional.empty();
  }

  /**
   * Marks read every unread event the user receives up to the given one in listing order. The count
   * of events marked, or empty if the given event does not exist or the user lacks it.
   */
  @Transactional
  Optional<MarkReadResult> markReadThrough(UUID id, Optional<UUID> user) {
    return repository
        .findByIdOptional(id)
        .filter(through -> receivedBy(through, user))
        .map(
            through -> {
              var now = toStoredInstant(Instant.now());
              return new MarkReadResult(
                  user.isPresent()
                      ? reads.markReadThrough(user.get(), through.createdAt(), through.id(), now)
                      : repository.markReadThrough(through, now));
            });
  }

  @Transactional
  UnreadCount countUnread(Optional<UUID> user) {
    return new UnreadCount(
        user.isPresent() ? reads.countUnread(user.get()) : repository.countUnread());
  }

  /**
   * Deletes the event, with its pending push, retries and delivery records; producers, clients and
   * other events are untouched. Returns whether it existed.
   */
  @Transactional
  boolean delete(UUID id) {
    var deleted = repository.deleteEvent(id);
    if (deleted) {
      LOG.infof("Deleted event %s", id);
    }
    return deleted;
  }

  /**
   * Deletes the events a request selects or filters, in one transaction, so a failure deletes none;
   * with a dry run, counts them and deletes none. Their pending pushes and retries go with them.
   * Empty if the filter names a producer that does not exist.
   */
  @Transactional
  Optional<DeletedEvents> delete(DeleteEventsRequest request) {
    var dryRun = request.dryRunRequested();
    if (request.selection()) {
      var ids = new LinkedHashSet<>(request.ids());
      if (dryRun) {
        return Optional.of(new DeletedEvents(repository.countIds(ids), true));
      }
      var count = repository.deleteIds(ids);
      LOG.infof("Deleted %d of %d selected events: %s", count, ids.size(), ids);
      return Optional.of(new DeletedEvents(count, false));
    }
    var producerId = Optional.ofNullable(request.producerId());
    if (producerId.isPresent() && producers.find(producerId.get()).isEmpty()) {
      return Optional.empty();
    }
    var createdBefore = Optional.ofNullable(request.createdBefore()).map(OffsetDateTime::toInstant);
    if (dryRun) {
      return Optional.of(
          new DeletedEvents(repository.countMatching(producerId, createdBefore), true));
    }
    var count = repository.deleteMatching(producerId, createdBefore);
    LOG.infof(
        "Deleted %d events %s",
        count,
        Stream.of(
                producerId.map(id -> "of producer " + id),
                createdBefore.map(before -> "created before " + before))
            .flatMap(Optional::stream)
            .collect(joining(" and ")));
    return Optional.of(new DeletedEvents(count, false));
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

  private static EventResponse toResponse(
      EventEntity event, ProducerIdentity producer, Instant readAt) {
    return new EventResponse(
        event.id(),
        new EventResponse.Producer(producer.id(), producer.name()),
        event.context(),
        event.category(),
        event.severity(),
        event.title(),
        event.message(),
        event.metadata(),
        event.link(),
        event.occurredAt(),
        event.createdAt(),
        readAt);
  }
}
