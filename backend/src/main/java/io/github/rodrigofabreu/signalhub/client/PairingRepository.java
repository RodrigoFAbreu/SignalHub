package io.github.rodrigofabreu.signalhub.client;

import io.quarkus.hibernate.orm.panache.PanacheRepositoryBase;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.persistence.LockModeType;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

@ApplicationScoped
class PairingRepository implements PanacheRepositoryBase<PairingEntity, UUID> {

  /**
   * The pairing with this code hash, holding its row lock until the transaction ends. A concurrent
   * redemption of the same code waits, then finds the row gone, so one code makes one client.
   */
  Optional<PairingEntity> findForRedemption(byte[] codeHash) {
    return find("codeHash", codeHash)
        .withLock(LockModeType.PESSIMISTIC_WRITE)
        .firstResultOptional();
  }

  /** Deletes the pairings that expired unredeemed; returns how many. */
  long deleteExpired(Instant now) {
    return delete("expiresAt <= ?1", now);
  }
}
