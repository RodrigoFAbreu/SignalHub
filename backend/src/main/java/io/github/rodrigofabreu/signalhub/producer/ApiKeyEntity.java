package io.github.rodrigofabreu.signalhub.producer;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

/**
 * Persistence mapping of the {@code producer_api_keys} table: a key's hash, never the key. Never
 * exposed through the HTTP API.
 */
@Entity
@Table(name = "producer_api_keys")
class ApiKeyEntity {

  // Assigned by the application, because the ID is part of the key that is hashed.
  @Id private UUID id;

  // Eager: authenticating a key always needs its producer, so load both in one query.
  @ManyToOne(optional = false)
  @JoinColumn(name = "producer_id", nullable = false, updatable = false)
  private ProducerEntity producer;

  @Column(name = "key_hash", nullable = false, updatable = false)
  private byte[] keyHash;

  @Column(name = "created_at", nullable = false, updatable = false)
  private Instant createdAt;

  @Column(name = "revoked_at")
  private Instant revokedAt;

  protected ApiKeyEntity() {}

  ApiKeyEntity(UUID id, ProducerEntity producer, byte[] keyHash, Instant createdAt) {
    this.id = id;
    this.producer = producer;
    this.keyHash = keyHash.clone();
    this.createdAt = createdAt;
  }

  UUID id() {
    return id;
  }

  ProducerEntity producer() {
    return producer;
  }

  byte[] keyHash() {
    return keyHash.clone();
  }

  Instant createdAt() {
    return createdAt;
  }

  Instant revokedAt() {
    return revokedAt;
  }

  boolean revoked() {
    return revokedAt != null;
  }

  /** Keeps the original time if already revoked, so repeating the request changes nothing. */
  void revoke(Instant now) {
    if (revokedAt == null) {
      revokedAt = now;
    }
  }
}
