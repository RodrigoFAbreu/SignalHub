package io.github.rodrigofabreu.signalhub.client;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

/**
 * Persistence mapping of the {@code web_sign_ins} table: a sign-in a web page has started, with the
 * hashes of its secrets, never the secrets. Never exposed through the HTTP API.
 */
@Entity
@Table(name = "web_sign_ins")
class WebSignInEntity {

  /** Where a sign-in is. A page learns it by polling; a device moves it on. */
  enum Status {
    /** Shown on the page, waiting for a device to look the code up. */
    PENDING,
    /** A device looked the code up and is asking its user. */
    ASKED,
    /** The user approved it; the page's next poll collects the session, once. */
    APPROVED,
    CANCELLED,
    /** The session was issued; the row only waits to be cleared. */
    SIGNED_IN
  }

  @Id private UUID id;

  @Column(name = "poll_hash", nullable = false, updatable = false)
  private byte[] pollHash;

  @Column(name = "code_hash", nullable = false, updatable = false)
  private byte[] codeHash;

  @Column(name = "scan_hash", nullable = false, updatable = false)
  private byte[] scanHash;

  @Column(name = "browser_name", nullable = false, updatable = false)
  private String browserName;

  @Column(name = "created_at", nullable = false, updatable = false)
  private Instant createdAt;

  @Column(name = "expires_at", nullable = false)
  private Instant expiresAt;

  @Enumerated(EnumType.STRING)
  @Column(nullable = false)
  private Status status = Status.PENDING;

  @Column(name = "asked_by")
  private UUID askedBy;

  @Column(name = "user_id")
  private UUID userId;

  protected WebSignInEntity() {}

  WebSignInEntity(
      UUID id,
      byte[] pollHash,
      byte[] codeHash,
      byte[] scanHash,
      String browserName,
      Instant createdAt,
      Instant expiresAt) {
    this.id = id;
    this.pollHash = pollHash.clone();
    this.codeHash = codeHash.clone();
    this.scanHash = scanHash.clone();
    this.browserName = browserName;
    this.createdAt = createdAt;
    this.expiresAt = expiresAt;
  }

  UUID id() {
    return id;
  }

  byte[] pollHash() {
    return pollHash.clone();
  }

  String browserName() {
    return browserName;
  }

  Instant expiresAt() {
    return expiresAt;
  }

  Status status() {
    return status;
  }

  UUID askedBy() {
    return askedBy;
  }

  UUID userId() {
    return userId;
  }

  void ask(UUID deviceId) {
    status = Status.ASKED;
    askedBy = deviceId;
  }

  /** The user approved it; the page has until {@code collectBy} to collect the session. */
  void approve(UUID approvedFor, Instant collectBy) {
    status = Status.APPROVED;
    userId = approvedFor;
    expiresAt = collectBy;
  }

  void cancel() {
    status = Status.CANCELLED;
  }

  void signedIn() {
    status = Status.SIGNED_IN;
  }
}
