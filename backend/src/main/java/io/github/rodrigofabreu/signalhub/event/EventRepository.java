package io.github.rodrigofabreu.signalhub.event;

import io.quarkus.hibernate.orm.panache.PanacheRepositoryBase;
import io.quarkus.panache.common.Sort;
import jakarta.enterprise.context.ApplicationScoped;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

@ApplicationScoped
class EventRepository implements PanacheRepositoryBase<EventEntity, UUID> {

  /** The listing order. {@code id} makes it total, since events can share a {@code createdAt}. */
  static final Sort NEWEST_FIRST = Sort.descending("createdAt", "id");

  /**
   * Up to {@code count} events matching the query, in {@link #NEWEST_FIRST} order, starting after
   * the query's cursor. Served by the {@code (created_at, id)} indexes of V3, so a page costs the
   * same however deep it is.
   */
  List<EventEntity> find(EventQuery query, int count) {
    var conditions = new ArrayList<String>();
    var parameters = new HashMap<String, Object>();
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
            : find(String.join(" and ", conditions), NEWEST_FIRST, parameters);
    return matching.range(0, count - 1).list();
  }

  /**
   * Waits until no other transaction is publishing with this producer's key, and holds the key
   * until this transaction ends, so concurrent requests with one key store one event. A lock on the
   * key rather than the unique index, whose violation would abort the transaction.
   */
  void lockIdempotencyKey(UUID producerId, String key) {
    getEntityManager()
        .createNativeQuery(
            "SELECT pg_advisory_xact_lock(hashtextextended(CAST(:producerId AS text) || ' ' || :key,"
                + " 0))")
        .setParameter("producerId", producerId)
        .setParameter("key", key)
        .getSingleResult();
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
