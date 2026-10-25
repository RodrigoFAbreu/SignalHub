package io.github.rodrigofabreu.signalhub.event;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.persistence.EntityManager;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

/**
 * Where the answers and closes of questions are stored: one row per event, whose primary key makes
 * the first of an answer and a close, or of two answers, win. Both are one {@code INSERT ...
 * SELECT} that also checks the question is still open on the clock the caller passes, so a question
 * cannot be answered after its {@code closesAt} however the requests interleave.
 */
@ApplicationScoped
class EventAnswers {

  private final EntityManager entityManager;

  EventAnswers(EntityManager entityManager) {
    this.entityManager = entityManager;
  }

  /**
   * Holds the event's row against deletion until the transaction ends, so an answer is never
   * inserted for an event that is deleted meanwhile. False if the event does not exist.
   */
  boolean lockEvent(UUID eventId) {
    return !entityManager
        .createNativeQuery("SELECT 1 FROM events WHERE id = :event FOR KEY SHARE")
        .setParameter("event", eventId)
        .getResultList()
        .isEmpty();
  }

  /**
   * Stores the answer unless the event is answered or closed, or closed by time; true if stored.
   */
  boolean insertAnswer(
      UUID eventId,
      UUID userId,
      String userName,
      String via,
      List<String> choiceIds,
      String text,
      UUID clientId,
      Instant now) {
    return entityManager
            .createNativeQuery(
                """
                INSERT INTO event_answers
                    (event_id, kind, user_id, user_name, via, choice_ids, text, answered_at,
                     client_id)
                SELECT e.id, 'ANSWER', :user, :name, :via, CAST(:choices AS text[]),
                       CAST(:text AS text), :now, :client
                FROM events e
                WHERE e.id = :event AND e.ask IS NOT NULL
                  AND (e.ask_closes_at IS NULL OR e.ask_closes_at > :now)
                ON CONFLICT (event_id) DO NOTHING
                """)
            .setParameter("event", eventId)
            .setParameter("user", userId)
            .setParameter("name", userName)
            .setParameter("via", via)
            .setParameter("choices", choiceIds.toArray(String[]::new))
            .setParameter("text", text)
            .setParameter("client", clientId)
            .setParameter("now", now)
            .executeUpdate()
        > 0;
  }

  /** Stores the producer's close unless the question ended already; true if stored. */
  boolean insertClose(UUID eventId, String note, Instant now) {
    return entityManager
            .createNativeQuery(
                """
                INSERT INTO event_answers (event_id, kind, note, answered_at)
                SELECT e.id, 'CLOSE', CAST(:note AS text), :now
                FROM events e
                WHERE e.id = :event AND e.ask IS NOT NULL
                  AND (e.ask_closes_at IS NULL OR e.ask_closes_at > :now)
                ON CONFLICT (event_id) DO NOTHING
                """)
            .setParameter("event", eventId)
            .setParameter("note", note)
            .setParameter("now", now)
            .executeUpdate()
        > 0;
  }

  Optional<EventAnswerEntity> find(UUID eventId) {
    return Optional.ofNullable(entityManager.find(EventAnswerEntity.class, eventId));
  }

  /** How each of the events ended; events still open are absent. */
  Map<UUID, EventAnswerEntity> find(Collection<UUID> eventIds) {
    if (eventIds.isEmpty()) {
      return Map.of();
    }
    return entityManager
        .createQuery("from EventAnswerEntity a where a.eventId in :ids", EventAnswerEntity.class)
        .setParameter("ids", eventIds)
        .getResultList()
        .stream()
        .collect(Collectors.toMap(EventAnswerEntity::eventId, Function.identity()));
  }
}
