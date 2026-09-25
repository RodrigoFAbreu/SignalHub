package io.github.rodrigofabreu.signalhub.event;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

/**
 * Persistence mapping of the {@code pending_pushes} table: an event whose push has not been
 * dispatched yet. Written with the event and deleted after dispatch.
 */
@Entity
@Table(name = "pending_pushes")
class PendingPushEntity {

  @Id
  @Column(name = "event_id")
  private UUID eventId;

  @Column(name = "queued_at", nullable = false, updatable = false)
  private Instant queuedAt;

  protected PendingPushEntity() {}

  PendingPushEntity(UUID eventId, Instant queuedAt) {
    this.eventId = eventId;
    this.queuedAt = queuedAt;
  }
}
