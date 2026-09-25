package io.github.rodrigofabreu.signalhub.event;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

/** Persistence mapping of the {@code push_dispatches} outbox: one row per undispatched event. */
@Entity
@Table(name = "push_dispatches")
class PushDispatchEntity {

  @Id
  @Column(name = "event_id")
  private UUID eventId;

  @Column(name = "created_at", nullable = false, updatable = false)
  private Instant createdAt;

  protected PushDispatchEntity() {}

  PushDispatchEntity(UUID eventId, Instant createdAt) {
    this.eventId = eventId;
    this.createdAt = createdAt;
  }
}
