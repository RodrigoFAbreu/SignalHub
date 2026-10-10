package io.github.rodrigofabreu.signalhub.client;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

/**
 * Persistence mapping of the {@code pairings} table: the hash of a pairing code, never the code,
 * the name of the client it registers and the user it is for, the device that created it, if one
 * did, and, once it is redeemed, when and as which client. Never exposed through the HTTP API.
 */
@Entity
@Table(name = "pairings")
class PairingEntity {

  @Id private UUID id;

  @Column(name = "code_hash", nullable = false, updatable = false)
  private byte[] codeHash;

  @Column(name = "client_name", nullable = false, updatable = false)
  private String clientName;

  // The user whose device the code registers.
  @Column(name = "user_id", nullable = false, updatable = false)
  private UUID userId;

  @Column(name = "created_at", nullable = false, updatable = false)
  private Instant createdAt;

  @Column(name = "expires_at", nullable = false, updatable = false)
  private Instant expiresAt;

  // Null when the operator created it with the admin token.
  @Column(name = "created_by", updatable = false)
  private UUID createdBy;

  // Both null until the code is redeemed; then it never redeems again.
  @Column(name = "redeemed_at")
  private Instant redeemedAt;

  @Column(name = "redeemed_by")
  private UUID redeemedBy;

  protected PairingEntity() {}

  PairingEntity(
      UUID id,
      byte[] codeHash,
      String clientName,
      UUID userId,
      Instant createdAt,
      Instant expiresAt,
      UUID createdBy) {
    this.id = id;
    this.codeHash = codeHash.clone();
    this.clientName = clientName;
    this.userId = userId;
    this.createdAt = createdAt;
    this.expiresAt = expiresAt;
    this.createdBy = createdBy;
  }

  UUID id() {
    return id;
  }

  String clientName() {
    return clientName;
  }

  UUID userId() {
    return userId;
  }

  Instant expiresAt() {
    return expiresAt;
  }

  /** The admin device that created this pairing; null if the operator did. */
  UUID createdBy() {
    return createdBy;
  }

  /** When the code was redeemed; null if it has not been. */
  Instant redeemedAt() {
    return redeemedAt;
  }

  /** The client the code registered; null if it has not been redeemed. */
  UUID redeemedBy() {
    return redeemedBy;
  }

  void redeem(UUID clientId, Instant at) {
    this.redeemedBy = clientId;
    this.redeemedAt = at;
  }
}
