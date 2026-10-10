package io.github.rodrigofabreu.signalhub.event;

import jakarta.persistence.Column;
import jakarta.persistence.Embeddable;
import jakarta.persistence.EmbeddedId;
import jakarta.persistence.Entity;
import jakarta.persistence.Table;
import java.io.Serializable;
import java.time.Instant;
import java.util.UUID;

/**
 * Persistence mapping of the {@code event_reads} table: that a user has read an event, on any of
 * their devices. Only queried, to filter the listing by read state; rows are written by {@link
 * EventReads}' own statements. Never exposed through the HTTP API.
 */
@Entity
@Table(name = "event_reads")
class EventReadEntity {

  @EmbeddedId private Key id;

  @Column(name = "read_at", nullable = false, updatable = false)
  private Instant readAt;

  protected EventReadEntity() {}

  /** The user and the event. */
  @Embeddable
  static class Key implements Serializable {

    private static final long serialVersionUID = 1L;

    @Column(name = "user_id")
    private UUID userId;

    @Column(name = "event_id")
    private UUID eventId;

    protected Key() {}

    @Override
    public boolean equals(Object other) {
      return other instanceof Key key
          && java.util.Objects.equals(userId, key.userId)
          && java.util.Objects.equals(eventId, key.eventId);
    }

    @Override
    public int hashCode() {
      return java.util.Objects.hash(userId, eventId);
    }
  }
}
