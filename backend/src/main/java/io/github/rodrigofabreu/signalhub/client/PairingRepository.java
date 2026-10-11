package io.github.rodrigofabreu.signalhub.client;

import io.quarkus.hibernate.orm.panache.PanacheRepositoryBase;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.persistence.LockModeType;
import java.time.Instant;
import java.util.List;
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

  /** As {@link #findByOperator}, holding its row lock, so it cannot be redeemed meanwhile. */
  Optional<PairingEntity> findByOperatorForUpdate(UUID id) {
    return find("id = ?1 and createdBy is null", id)
        .withLock(LockModeType.PESSIMISTIC_WRITE)
        .firstResultOptional();
  }

  /** The operator's pairings not redeemed and not expired at this time, soonest to expire first. */
  List<PairingEntity> openByOperator(Instant time) {
    return list(
        "createdBy is null and redeemedAt is null and expiresAt > ?1 order by expiresAt, id", time);
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
