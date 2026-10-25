package io.github.rodrigofabreu.signalhub.event;

import io.quarkus.hibernate.orm.panache.PanacheRepositoryBase;
import io.quarkus.panache.common.Sort;
import jakarta.enterprise.context.ApplicationScoped;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

@ApplicationScoped
class EventRepository implements PanacheRepositoryBase<EventEntity, UUID> {

  /** The listing order. {@code id} makes it total, since events can share a {@code createdAt}. */
  static final Sort NEWEST_FIRST = Sort.descending("createdAt", "id");

  /**
   * Up to {@code count} events matching the query, in {@link #NEWEST_FIRST} order, starting after
   * the query's cursor. Served by the {@code (created_at, id)} indexes of V3, and unread events by
   * the partial index of V6, so a page costs the same however deep it is.
   */
  List<EventEntity> find(
      EventQuery query, int count, Optional<Viewer> viewer, Optional<Set<UUID>> userProducerIds) {
    var filter = Filter.of(query, viewer, userProducerIds, Instant.now());
    if (filter.isEmpty()) {
      return List.of();
    }
    var conditions = filter.conditions();
    var parameters = filter.parameters();
    query
        .after()
        .ifPresent(
            cursor -> {
              // A row comparison, which PostgreSQL answers with one index range scan.
              conditions.add("(createdAt, id) < (:afterCreatedAt, :afterId)");
              parameters.put("afterCreatedAt", cursor.createdAt());
              parameters.put("afterId", cursor.id());
            });
    var matching =
        conditions.isEmpty()
            ? findAll(NEWEST_FIRST)
            : find(
                "from EventEntity e where " + String.join(" and ", conditions),
                NEWEST_FIRST,
                parameters);
    return matching.range(0, count - 1).list();
  }

  /**
   * How many events match the query's filters, ignoring its cursor and limit. Counts the matching
   * rows, so it costs more the more events match: the listing runs it only when asked.
   */
  long countListed(EventQuery query, Optional<Viewer> viewer, Optional<Set<UUID>> userProducerIds) {
    var filter = Filter.of(query, viewer, userProducerIds, Instant.now());
    if (filter.isEmpty()) {
      return 0;
    }
    return filter.conditions().isEmpty()
        ? count()
        : count(
            "from EventEntity e where " + String.join(" and ", filter.conditions()),
            filter.parameters());
  }

  /** The delivery records of the events, for their push summaries. */
  List<PushSummary.Record> deliveryRecords(Collection<UUID> eventIds) {
    return getEntityManager()
        .createQuery(
            "select d.eventId, d.clientId, d.attempt, d.outcome from EventDeliveryEntity d"
                + " where d.eventId in :ids",
            Object[].class)
        .setParameter("ids", eventIds)
        .getResultList()
        .stream()
        .map(
            row ->
                new PushSummary.Record(
                    (UUID) row[0],
                    (UUID) row[1],
                    ((Number) row[2]).intValue(),
                    DeliveryOutcome.valueOf((String) row[3])))
        .toList();
  }

  /** Which of the events still wait in the push outbox. */
  List<UUID> pendingPushes(Collection<UUID> eventIds) {
    return getEntityManager()
        .createQuery(
            "select p.eventId from PushDispatchEntity p where p.eventId in :ids", UUID.class)
        .setParameter("ids", eventIds)
        .getResultList();
  }

  /**
   * The conditions of a listing's filters and their parameters, without the cursor. Empty if no
   * event can match.
   */
  private record Filter(boolean isEmpty, List<String> conditions, Map<String, Object> parameters) {

    /** The condition that an event's question stands as the filter says. */
    static String state(AnswerFilter filter) {
      return switch (filter) {
        case NONE -> "ask is null";
        case OPEN -> OPEN;
        case ANSWERED -> ENDED + " and a.kind = 'ANSWER')";
        case CLOSED ->
            "("
                + ENDED
                + " and a.kind = 'CLOSE') or (ask is not null and not "
                + ENDED
                + ") and askClosesAt <= :now))";
      };
    }

    static Filter of(
        EventQuery query,
        Optional<Viewer> viewer,
        Optional<Set<UUID>> userProducerIds,
        Instant now) {
      var conditions = new ArrayList<String>();
      var parameters = new HashMap<String, Object>();
      if ((viewer.isPresent() && viewer.get().producerIds().isEmpty())
          || (userProducerIds.isPresent() && userProducerIds.get().isEmpty())
          // Only a user answers: for the operator, or a user who answers nothing, none can match.
          || (query.toAnswer() && viewer.map(v -> v.answerable().isEmpty()).orElse(true))) {
        return new Filter(true, conditions, parameters);
      }
      if (query.toAnswer()) {
        conditions.add("producerId in :answerable");
        parameters.put("answerable", viewer.get().answerable());
        conditions.add(OPEN);
        parameters.put("now", now);
      }
      if (!query.answerStates().isEmpty()) {
        conditions.add(
            query.answerStates().stream()
                .map(Filter::state)
                .collect(Collectors.joining(" or ", "(", ")")));
        // A named parameter nothing uses is an error.
        if (!Set.of(AnswerFilter.ANSWERED, AnswerFilter.NONE).containsAll(query.answerStates())) {
          parameters.put("now", now);
        }
      }
      viewer.ifPresent(
          v -> {
            // Only events of the producers the viewer's user is subscribed to.
            conditions.add("producerId in :viewerProducers");
            parameters.put("viewerProducers", v.producerIds());
          });
      userProducerIds.ifPresent(
          ids -> {
            // The operator's per-user view: the producers a user owns or is subscribed to.
            conditions.add("producerId in :userProducers");
            parameters.put("userProducers", ids);
          });
      if (!query.producerIds().isEmpty()) {
        conditions.add("producerId in :producerIds");
        parameters.put("producerIds", query.producerIds());
      }
      if (!query.categories().isEmpty()) {
        conditions.add("category in :categories");
        parameters.put("categories", query.categories());
      }
      if (!query.severities().isEmpty()) {
        conditions.add("severity in :severities");
        parameters.put("severities", query.severities());
      }
      query
          .read()
          .ifPresent(
              read -> {
                viewer.ifPresent(v -> parameters.put("viewerUser", v.userId()));
                conditions.add(
                    viewer.isPresent()
                        // A user's read state is theirs alone.
                        ? (read ? "exists " : "not exists ")
                            + "(select 1 from EventReadEntity r where r.id.eventId = e.id"
                            + " and r.id.userId = :viewerUser)"
                        // Literal predicates: "read_at is null" is the one the partial index of V6
                        // matches.
                        : (read ? "readAt is not null" : "readAt is null"));
              });
      query
          .createdFrom()
          .ifPresent(
              from -> {
                conditions.add("createdAt >= :createdFrom");
                parameters.put("createdFrom", from);
              });
      query
          .createdBefore()
          .ifPresent(
              before -> {
                conditions.add("createdAt < :createdBefore");
                parameters.put("createdBefore", before);
              });
      if (!query.push().isEmpty()) {
        conditions.add(
            query.push().stream()
                .map(PushPredicates::of)
                .collect(Collectors.joining(" or ", "(", ")")));
      }
      return new Filter(false, conditions, parameters);
    }
  }

  /**
   * Whose events a listing is limited to: a user, the producers they are subscribed to, and (when
   * the listing needs it) those whose questions they may answer.
   */
  record Viewer(UUID userId, Set<UUID> producerIds, Set<UUID> answerable) {}

  private static final String ENDED =
      "exists (select 1 from EventAnswerEntity a where a.eventId = e.id";

  /** An open question: it asks, nobody answered or closed it, and its closesAt has not passed. */
  private static final String OPEN =
      "(ask is not null and not " + ENDED + ") and (askClosesAt is null or askClosesAt > :now))";

  /** How many open questions the viewer may answer. */
  long countToAnswer(Viewer viewer, Instant now) {
    if (viewer.answerable().isEmpty()) {
      return 0;
    }
    return count(
        "from EventEntity e where producerId in :answerable and " + OPEN,
        Map.of("answerable", viewer.answerable(), "now", now));
  }

  /** How many of the given events exist and ask. */
  long countAskingIds(Collection<UUID> ids) {
    return count("id in ?1 and ask is not null", ids);
  }

  /** How many events match the filter and ask; as {@link #countMatching}. */
  long countAskingMatching(Optional<UUID> producerId, Optional<Instant> createdBefore) {
    var filter = DeleteFilter.of(producerId, createdBefore);
    return count(filter.query() + " and ask is not null", filter.parameters());
  }

  /**
   * Waits until no other transaction is publishing and holds the lock until this transaction ends,
   * so events commit one at a time in {@code createdAt} order: a reader that sees an event also
   * sees every event listed after it. Also makes concurrent requests with one idempotency key store
   * one event, without relying on the unique index, whose violation would abort the transaction.
   */
  void lockPublishing() {
    getEntityManager()
        .createNativeQuery("SELECT pg_advisory_xact_lock(hashtextextended('signalhub.publish', 0))")
        .getSingleResult();
  }

  /** The newest stored {@code createdAt}, if any event is stored. */
  Optional<Instant> latestCreatedAt() {
    return Optional.ofNullable(
        getEntityManager()
            .createQuery("SELECT max(e.createdAt) FROM EventEntity e", Instant.class)
            .getSingleResult());
  }

  Optional<EventEntity> findByIdempotencyKey(UUID producerId, String key) {
    return find("producerId = ?1 and idempotencyKey = ?2", producerId, key).firstResultOptional();
  }

  /** Whether two metadata documents are equal as {@code jsonb}, as they are stored. */
  boolean sameMetadata(String stored, String sent) {
    return (Boolean)
        getEntityManager()
            .createNativeQuery("SELECT CAST(:stored AS jsonb) = CAST(:sent AS jsonb)")
            .setParameter("stored", stored)
            .setParameter("sent", sent)
            .getSingleResult();
  }

  /**
   * Marks the event read at {@code now} unless it already is, keeping the first read time. Returns
   * whether the event exists.
   */
  boolean markRead(UUID id, Instant now) {
    return update("readAt = ?1 where id = ?2 and readAt is null", now, id) == 1
        || count("id", id) == 1;
  }

  /** Marks the event unread. Returns whether it exists. */
  boolean markUnread(UUID id) {
    return update("readAt = null where id = ?1", id) == 1;
  }

  /**
   * Marks read every unread event at or before {@code through} in listing order, so events newer
   * than the ones the owner has seen stay unread. Served by the partial index of V6.
   */
  int markReadThrough(EventEntity through, Instant now) {
    return update(
        "readAt = ?1 where readAt is null and (createdAt, id) <= (?2, ?3)",
        now,
        through.createdAt(),
        through.id());
  }

  long countUnread() {
    return count("readAt is null");
  }

  /**
   * Deletes the event, with its pending push, retries and delivery records. Returns whether it
   * existed.
   */
  boolean deleteEvent(UUID id) {
    return delete("id", id) == 1;
  }

  /** How many of the given events exist. */
  long countIds(Collection<UUID> ids) {
    return count("id in ?1", ids);
  }

  /**
   * Deletes the given events that exist, with their pending pushes and retries; returns how many.
   */
  long deleteIds(Collection<UUID> ids) {
    return delete("id in ?1", ids);
  }

  /** How many events match the filter; an absent bound does not restrict. */
  long countMatching(Optional<UUID> producerId, Optional<Instant> createdBefore) {
    var filter = DeleteFilter.of(producerId, createdBefore);
    return count(filter.query(), filter.parameters());
  }

  /**
   * Deletes every event matching the filter, with their pending pushes and retries (the foreign
   * keys of {@code push_dispatches} and {@code push_retries} cascade); returns how many.
   */
  long deleteMatching(Optional<UUID> producerId, Optional<Instant> createdBefore) {
    var filter = DeleteFilter.of(producerId, createdBefore);
    return delete(filter.query(), filter.parameters());
  }

  private record DeleteFilter(String query, Map<String, Object> parameters) {
    static DeleteFilter of(Optional<UUID> producerId, Optional<Instant> createdBefore) {
      var conditions = new ArrayList<String>();
      var parameters = new HashMap<String, Object>();
      producerId.ifPresent(
          id -> {
            conditions.add("producerId = :producerId");
            parameters.put("producerId", id);
          });
      createdBefore.ifPresent(
          before -> {
            conditions.add("createdAt < :createdBefore");
            parameters.put("createdBefore", before);
          });
      if (conditions.isEmpty()) {
        // Never "every event" by accident: a filter always restricts.
        throw new IllegalArgumentException("A filter needs a producer or a time");
      }
      return new DeleteFilter(String.join(" and ", conditions), parameters);
    }
  }

  /**
   * Deletes up to {@code limit} of the oldest events created before {@code cutoff}, found through
   * the {@code (created_at, id)} index of V3. The foreign keys of {@code push_dispatches} and
   * {@code push_retries} cascade. Rows another transaction holds (being marked read) are left for
   * the next run.
   */
  int deleteCreatedBefore(Instant cutoff, int limit) {
    return getEntityManager()
        .createNativeQuery(
            """
            DELETE FROM events WHERE id IN (
                SELECT id FROM events
                WHERE created_at < :cutoff
                ORDER BY created_at, id
                LIMIT :limit
                FOR UPDATE SKIP LOCKED)
            """)
        .setParameter("cutoff", cutoff)
        .setParameter("limit", limit)
        .executeUpdate();
  }
}
