package io.github.rodrigofabreu.signalhub.client;

import io.quarkus.hibernate.orm.panache.PanacheRepositoryBase;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.persistence.LockModeType;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

@ApplicationScoped
class WebSignInRepository implements PanacheRepositoryBase<WebSignInEntity, UUID> {

  Optional<WebSignInEntity> findForUpdate(UUID id) {
    return findByIdOptional(id, LockModeType.PESSIMISTIC_WRITE);
  }

  /** The sign-in a typed code or a scanned code belongs to, locked until the transaction ends. */
  Optional<WebSignInEntity> findByCodeForUpdate(byte[] hash) {
    return find("codeHash = ?1 or scanHash = ?1", hash)
        .withLock(LockModeType.PESSIMISTIC_WRITE)
        .firstResultOptional();
  }

  /** How many sign-ins a page could still be waiting on. */
  long countOpen(Instant now) {
    return count("expiresAt > ?1 and status in ('PENDING', 'ASKED')", now);
  }

  long deleteExpiredBy(Instant time) {
    return delete("expiresAt <= ?1", time);
  }
}
