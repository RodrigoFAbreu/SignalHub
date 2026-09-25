package io.github.rodrigofabreu.signalhub.client;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

/**
 * Persistence mapping of the {@code clients} table: a client's key hash, never the key, and its
 * push target. Never exposed through the HTTP API.
 */
@Entity
@Table(name = "clients")
class ClientEntity {

  // Assigned by the application, because the ID is part of the key that is hashed.
  @Id private UUID id;

  @Column(nullable = false, updatable = false)
  private String name;

  @Column(name = "key_hash", nullable = false, updatable = false)
  private byte[] keyHash;

  @Column(name = "created_at", nullable = false, updatable = false)
  private Instant createdAt;

  @Column(name = "revoked_at")
  private Instant revokedAt;

  @Column(name = "push_provider")
  private String pushProvider;

  @Column(name = "push_token")
  private String pushToken;

  @Column(name = "push_updated_at")
  private Instant pushUpdatedAt;

  protected ClientEntity() {}

  ClientEntity(UUID id, String name, byte[] keyHash, Instant createdAt) {
    this.id = id;
    this.name = name;
    this.keyHash = keyHash.clone();
    this.createdAt = createdAt;
  }

  UUID id() {
    return id;
  }

  String name() {
    return name;
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

  String pushProvider() {
    return pushProvider;
  }

  String pushToken() {
    return pushToken;
  }

  Instant pushUpdatedAt() {
    return pushUpdatedAt;
  }

  /**
   * Keeps the original time if already revoked, so repeating the request changes nothing. A revoked
   * client must never receive pushes, so its push target goes too.
   */
  void revoke(Instant now) {
    if (revokedAt == null) {
      revokedAt = now;
    }
    clearPushTarget();
  }

  void setPushTarget(String provider, String token, Instant now) {
    pushProvider = provider;
    pushToken = token;
    pushUpdatedAt = now;
  }

  void clearPushTarget() {
    pushProvider = null;
    pushToken = null;
    pushUpdatedAt = null;
  }
}
