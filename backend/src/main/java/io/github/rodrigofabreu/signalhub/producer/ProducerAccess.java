package io.github.rodrigofabreu.signalhub.producer;

import io.github.rodrigofabreu.signalhub.user.NamedUser;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.persistence.EntityManager;
import jakarta.transaction.Transactional;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Collection;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import org.jboss.logging.Logger;

/**
 * Who sees which producer, and who receives its events. A producer is seen by its owner and, if it
 * is public, by every user; a private one also by the users on its allow-list. A user receives the
 * events of the producers they are subscribed to, and subscribes only to producers they see.
 * Everything that decides what a user may get from a producer goes through here. Logs only IDs.
 */
@ApplicationScoped
public class ProducerAccess {

  private static final Logger LOG = Logger.getLogger(ProducerAccess.class);

  private final EntityManager entityManager;

  ProducerAccess(EntityManager entityManager) {
    this.entityManager = entityManager;
  }

  /** Whether the user sees the producer: they own it, it is public, or they are allowed on it. */
  @Transactional
  public boolean canSee(UUID userId, UUID producerId) {
    return exists(
        """
        SELECT 1 FROM producers p
        WHERE p.id = :producer
          AND (p.visibility = 'PUBLIC'
               OR p.owner_id = :user
               OR EXISTS (SELECT 1 FROM producer_allowed_users a
                          WHERE a.producer_id = p.id AND a.user_id = :user))
        """,
        userId,
        producerId);
  }

  /**
   * Subscribes the user to the producer; false, and nothing changes, if they do not see it.
   * Subscribing twice changes nothing.
   */
  @Transactional
  public boolean subscribe(UUID userId, UUID producerId) {
    // The producer's row lock serialises this with a change of its visibility or allow-list, which
    // takes the same lock, so a user who just lost sight of it cannot subscribe behind that change.
    entityManager
        .createNativeQuery("SELECT 1 FROM producers WHERE id = :producer FOR UPDATE")
        .setParameter("producer", producerId)
        .getResultList();
    if (!canSee(userId, producerId)) {
      return false;
    }
    insertSubscription(userId, producerId);
    return true;
  }

  /** Ends the subscription. Returns whether there was one. */
  @Transactional
  public boolean unsubscribe(UUID userId, UUID producerId) {
    var ended =
        entityManager
            .createNativeQuery(
                "DELETE FROM subscriptions WHERE user_id = :user AND producer_id = :producer")
            .setParameter("user", userId)
            .setParameter("producer", producerId)
            .executeUpdate();
    if (ended > 0) {
      LOG.infof("User %s unsubscribed from producer %s", userId, producerId);
    }
    return ended > 0;
  }

  /** Whether the user receives the producer's events. */
  @Transactional
  public boolean isSubscribed(UUID userId, UUID producerId) {
    return exists(
        "SELECT 1 FROM subscriptions WHERE user_id = :user AND producer_id = :producer",
        userId,
        producerId);
  }

  /** The producers the user sees: public ones, their own, and those they are allowed on. */
  @Transactional
  public List<UUID> visibleProducerIds(UUID userId) {
    List<?> ids =
        entityManager
            .createNativeQuery(
                """
                SELECT p.id FROM producers p
                WHERE p.visibility = 'PUBLIC'
                   OR p.owner_id = :user
                   OR EXISTS (SELECT 1 FROM producer_allowed_users a
                              WHERE a.producer_id = p.id AND a.user_id = :user)
                """)
            .setParameter("user", userId)
            .getResultList();
    return ids.stream().map(UUID.class::cast).toList();
  }

  /** The producers the user receives events from. */
  @Transactional
  public Set<UUID> subscribedProducerIds(UUID userId) {
    List<?> ids =
        entityManager
            .createNativeQuery("SELECT producer_id FROM subscriptions WHERE user_id = :user")
            .setParameter("user", userId)
            .getResultList();
    return new HashSet<>(ids.stream().map(UUID.class::cast).toList());
  }

  /** The producers the user owns. */
  @Transactional
  public Set<UUID> ownedProducerIds(UUID userId) {
    List<?> ids =
        entityManager
            .createNativeQuery("SELECT id FROM producers WHERE owner_id = :user")
            .setParameter("user", userId)
            .getResultList();
    return new HashSet<>(ids.stream().map(UUID.class::cast).toList());
  }

  /** The users who receive this producer's events. */
  @Transactional
  public Set<UUID> subscribers(UUID producerId) {
    List<?> ids =
        entityManager
            .createNativeQuery("SELECT user_id FROM subscriptions WHERE producer_id = :producer")
            .setParameter("producer", producerId)
            .getResultList();
    return new HashSet<>(ids.stream().map(UUID.class::cast).toList());
  }

  /** The owner is subscribed to their producer from the moment it exists. */
  void subscribeOwner(UUID userId, UUID producerId) {
    insertSubscription(userId, producerId);
  }

  /** Replaces the producer's allow-list. */
  void setAllowed(UUID producerId, Collection<UUID> userIds) {
    entityManager
        .createNativeQuery("DELETE FROM producer_allowed_users WHERE producer_id = :producer")
        .setParameter("producer", producerId)
        .executeUpdate();
    for (var userId : userIds) {
      entityManager
          .createNativeQuery(
              "INSERT INTO producer_allowed_users (producer_id, user_id) VALUES (:producer, :user)")
          .setParameter("producer", producerId)
          .setParameter("user", userId)
          .executeUpdate();
    }
  }

  /** Puts the user on the allow-list; false if they already were. */
  boolean allow(UUID producerId, UUID userId) {
    return entityManager
            .createNativeQuery(
                """
                INSERT INTO producer_allowed_users (producer_id, user_id) VALUES (:producer, :user)
                ON CONFLICT DO NOTHING
                """)
            .setParameter("producer", producerId)
            .setParameter("user", userId)
            .executeUpdate()
        > 0;
  }

  /** Takes the user off the allow-list; false if they were not on it. */
  boolean disallow(UUID producerId, UUID userId) {
    return entityManager
            .createNativeQuery(
                "DELETE FROM producer_allowed_users WHERE producer_id = :producer"
                    + " AND user_id = :user")
            .setParameter("producer", producerId)
            .setParameter("user", userId)
            .executeUpdate()
        > 0;
  }

  /** The users on the producer's allow-list. */
  List<UUID> allowed(UUID producerId) {
    List<?> ids =
        entityManager
            .createNativeQuery(
                "SELECT user_id FROM producer_allowed_users WHERE producer_id = :producer")
            .setParameter("producer", producerId)
            .getResultList();
    return ids.stream().map(UUID.class::cast).toList();
  }

  /** {@link #allowed} of every producer that has anyone on its allow-list. */
  java.util.Map<UUID, List<UUID>> allowedByProducer() {
    var allowed = new java.util.HashMap<UUID, List<UUID>>();
    for (var row :
        entityManager
            .createNativeQuery("SELECT producer_id, user_id FROM producer_allowed_users")
            .getResultList()) {
      var columns = (Object[]) row;
      allowed
          .computeIfAbsent((UUID) columns[0], k -> new java.util.ArrayList<>())
          .add((UUID) columns[1]);
    }
    return allowed;
  }

  // ---- Who may answer the questions of a producer's events: its owner, and the users the owner
  // names. An answerer must see the producer; losing sight of it, or being revoked, ends it.

  /**
   * Whether the user may answer the producer's questions: they own it or are one of its answerers.
   */
  @Transactional
  public boolean canAnswer(UUID userId, UUID producerId) {
    return exists(
        """
        SELECT 1 FROM producers p
        WHERE p.id = :producer
          AND (p.owner_id = :user
               OR EXISTS (SELECT 1 FROM producer_answerers a
                          WHERE a.producer_id = p.id AND a.user_id = :user))
        """,
        userId,
        producerId);
  }

  /** The producers whose questions the user may answer. */
  @Transactional
  public Set<UUID> answerableProducerIds(UUID userId) {
    List<?> ids =
        entityManager
            .createNativeQuery(
                """
                SELECT id FROM producers WHERE owner_id = :user
                UNION
                SELECT producer_id FROM producer_answerers WHERE user_id = :user
                """)
            .setParameter("user", userId)
            .getResultList();
    return new HashSet<>(ids.stream().map(UUID.class::cast).toList());
  }

  /**
   * Who may answer each producer's questions, by name: the owner first, then the answerers by name.
   * Revoked users are left out, so the list may be empty.
   */
  @Transactional
  public java.util.Map<UUID, List<NamedUser>> whoCanAnswer(Collection<UUID> producerIds) {
    var who = new java.util.HashMap<UUID, List<NamedUser>>();
    if (producerIds.isEmpty()) {
      return who;
    }
    for (var row :
        entityManager
            .createNativeQuery(
                """
                SELECT p.id, u.id, u.name, 0 FROM producers p
                JOIN users u ON u.id = p.owner_id
                WHERE p.id IN :producers AND u.revoked_at IS NULL
                UNION ALL
                SELECT a.producer_id, u.id, u.name, 1 FROM producer_answerers a
                JOIN users u ON u.id = a.user_id
                WHERE a.producer_id IN :producers AND u.revoked_at IS NULL
                  AND a.user_id <> (SELECT owner_id FROM producers WHERE id = a.producer_id)
                ORDER BY 1, 4, 3
                """)
            .setParameter("producers", producerIds)
            .getResultList()) {
      var columns = (Object[]) row;
      who.computeIfAbsent((UUID) columns[0], k -> new java.util.ArrayList<>())
          .add(new NamedUser((UUID) columns[1], (String) columns[2]));
    }
    return who;
  }

  /** The users the owner named to answer the producer's questions. */
  List<UUID> answerers(UUID producerId) {
    List<?> ids =
        entityManager
            .createNativeQuery(
                "SELECT user_id FROM producer_answerers WHERE producer_id = :producer")
            .setParameter("producer", producerId)
            .getResultList();
    return ids.stream().map(UUID.class::cast).toList();
  }

  /** {@link #answerers} of every producer that has any. */
  java.util.Map<UUID, List<UUID>> answerersByProducer() {
    var answerers = new java.util.HashMap<UUID, List<UUID>>();
    for (var row :
        entityManager
            .createNativeQuery("SELECT producer_id, user_id FROM producer_answerers")
            .getResultList()) {
      var columns = (Object[]) row;
      answerers
          .computeIfAbsent((UUID) columns[0], k -> new java.util.ArrayList<>())
          .add((UUID) columns[1]);
    }
    return answerers;
  }

  /** Names the user an answerer of the producer; false if they already were. */
  boolean addAnswerer(UUID producerId, UUID userId) {
    return entityManager
            .createNativeQuery(
                """
                INSERT INTO producer_answerers (producer_id, user_id) VALUES (:producer, :user)
                ON CONFLICT DO NOTHING
                """)
            .setParameter("producer", producerId)
            .setParameter("user", userId)
            .executeUpdate()
        > 0;
  }

  /** Takes the user off the producer's answerers; false if they were not on the list. */
  boolean removeAnswerer(UUID producerId, UUID userId) {
    return entityManager
            .createNativeQuery(
                "DELETE FROM producer_answerers WHERE producer_id = :producer AND user_id = :user")
            .setParameter("producer", producerId)
            .setParameter("user", userId)
            .executeUpdate()
        > 0;
  }

  /** Takes the user off every producer's answerers, as when they are revoked. */
  public void removeAnswererEverywhere(UUID userId) {
    var ended =
        entityManager
            .createNativeQuery("DELETE FROM producer_answerers WHERE user_id = :user")
            .setParameter("user", userId)
            .executeUpdate();
    if (ended > 0) {
      LOG.infof("User %s is no longer an answerer of %d producers", userId, ended);
    }
  }

  /**
   * Ends the subscriptions, and the answerer roles, of the users who no longer see the producer:
   * when it is private, every one who is neither its owner nor on its allow-list.
   */
  void endSubscriptionsWithoutSight(UUID producerId) {
    entityManager
        .createNativeQuery(
            """
            DELETE FROM producer_answerers an USING producers p
            WHERE an.producer_id = p.id AND p.id = :producer AND p.visibility = 'PRIVATE'
              AND an.user_id <> p.owner_id
              AND NOT EXISTS (SELECT 1 FROM producer_allowed_users a
                              WHERE a.producer_id = p.id AND a.user_id = an.user_id)
            """)
        .setParameter("producer", producerId)
        .executeUpdate();
    var ended =
        entityManager
            .createNativeQuery(
                """
                DELETE FROM subscriptions s USING producers p
                WHERE s.producer_id = p.id AND p.id = :producer AND p.visibility = 'PRIVATE'
                  AND s.user_id <> p.owner_id
                  AND NOT EXISTS (SELECT 1 FROM producer_allowed_users a
                                  WHERE a.producer_id = p.id AND a.user_id = s.user_id)
                """)
            .setParameter("producer", producerId)
            .executeUpdate();
    if (ended > 0) {
      LOG.infof("Ended %d subscriptions of producer %s that lost sight of it", ended, producerId);
    }
  }

  private void insertSubscription(UUID userId, UUID producerId) {
    var created =
        entityManager
            .createNativeQuery(
                """
                INSERT INTO subscriptions (user_id, producer_id, created_at)
                VALUES (:user, :producer, :at)
                ON CONFLICT DO NOTHING
                """)
            .setParameter("user", userId)
            .setParameter("producer", producerId)
            .setParameter("at", Instant.now().truncatedTo(ChronoUnit.MICROS))
            .executeUpdate();
    if (created > 0) {
      LOG.infof("User %s subscribed to producer %s", userId, producerId);
    }
  }

  private boolean exists(String sql, UUID userId, UUID producerId) {
    return !entityManager
        .createNativeQuery(sql)
        .setParameter("user", userId)
        .setParameter("producer", producerId)
        .getResultList()
        .isEmpty();
  }
}
