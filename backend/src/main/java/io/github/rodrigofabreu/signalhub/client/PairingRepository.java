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
   * redemption of the same code waits, then finds it redeemed or gone, so one code makes one
   * client.
   */
  Optional<PairingEntity> findForRedemption(byte[] codeHash) {
    return find("codeHash", codeHash)
        .withLock(LockModeType.PESSIMISTIC_WRITE)
        .firstResultOptional();
  }

  /** The pairing with this ID the operator created, with the admin token. */
  Optional<PairingEntity> findByOperator(UUID id) {
    return find("id = ?1 and createdBy is null", id).firstResultOptional();
  }

  /** The pairing with this ID this admin device created. */
  Optional<PairingEntity> findByCreator(UUID id, UUID createdBy) {
    return find("id = ?1 and createdBy = ?2", id, createdBy).firstResultOptional();
  }

  /**
   * Deletes the pairings, redeemed or not, that expired at or before this time; returns how many.
   */
  long deleteExpiredBy(Instant time) {
    return delete("expiresAt <= ?1", time);
  }
}
