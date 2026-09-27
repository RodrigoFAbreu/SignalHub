package io.github.rodrigofabreu.signalhub.client;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

/**
 * Persistence mapping of the {@code pairings} table: the hash of an unredeemed pairing code, never
 * the code, and the name of the client it will register. Never exposed through the HTTP API.
 */
@Entity
@Table(name = "pairings")
class PairingEntity {

  @Id private UUID id;

  @Column(name = "code_hash", nullable = false, updatable = false)
  private byte[] codeHash;

  @Column(name = "client_name", nullable = false, updatable = false)
  private String clientName;

  @Column(name = "created_at", nullable = false, updatable = false)
  private Instant createdAt;

  @Column(name = "expires_at", nullable = false, updatable = false)
  private Instant expiresAt;

  protected PairingEntity() {}

  PairingEntity(UUID id, byte[] codeHash, String clientName, Instant createdAt, Instant expiresAt) {
    this.id = id;
    this.codeHash = codeHash.clone();
    this.clientName = clientName;
    this.createdAt = createdAt;
    this.expiresAt = expiresAt;
  }

  UUID id() {
    return id;
  }

  String clientName() {
    return clientName;
  }

  Instant expiresAt() {
    return expiresAt;
  }
}
