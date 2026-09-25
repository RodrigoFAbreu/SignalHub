package io.github.rodrigofabreu.signalhub.event;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.annotations.UuidGenerator;
import org.hibernate.type.SqlTypes;

/** Persistence mapping of the {@code events} table. Never exposed through the HTTP API. */
@Entity
@Table(name = "events")
class EventEntity {

  // UUIDv7 keeps inserts append-mostly in the primary key index and sorts roughly by creation.
  @Id
  @UuidGenerator(style = UuidGenerator.Style.VERSION_7)
  private UUID id;

  // The authenticated producer that published the event.
  @Column(name = "producer_id", nullable = false, updatable = false)
  private UUID producerId;

  @Column(updatable = false)
  private String context;

  @Enumerated(EnumType.STRING)
  @Column(nullable = false, updatable = false)
  private Category category;

  @Enumerated(EnumType.STRING)
  @Column(nullable = false, updatable = false)
  private Severity severity;

  @Column(nullable = false, updatable = false)
  private String title;

  @Column(updatable = false)
  private String message;

  // Kept as JSON text: SignalHub never looks inside producer metadata.
  @JdbcTypeCode(SqlTypes.JSON)
  @Column(nullable = false, updatable = false)
  private String metadata;

  @Column(name = "occurred_at", updatable = false)
  private Instant occurredAt;

  @Column(name = "created_at", nullable = false, updatable = false)
  private Instant createdAt;

  // Changed only by the bulk updates in EventRepository, so concurrent marks never overwrite.
  @Column(name = "read_at", updatable = false)
  private Instant readAt;

  protected EventEntity() {}

  EventEntity(
      UUID producerId,
      String context,
      Category category,
      Severity severity,
      String title,
      String message,
      String metadata,
      Instant occurredAt,
      Instant createdAt) {
    this.producerId = producerId;
    this.context = context;
    this.category = category;
    this.severity = severity;
    this.title = title;
    this.message = message;
    this.metadata = metadata;
    this.occurredAt = occurredAt;
    this.createdAt = createdAt;
  }

  UUID id() {
    return id;
  }

  UUID producerId() {
    return producerId;
  }

  String context() {
    return context;
  }

  Category category() {
    return category;
  }

  Severity severity() {
    return severity;
  }

  String title() {
    return title;
  }

  String message() {
    return message;
  }

  String metadata() {
    return metadata;
  }

  Instant occurredAt() {
    return occurredAt;
  }

  Instant createdAt() {
    return createdAt;
  }

  Instant readAt() {
    return readAt;
  }
}
