package io.github.rodrigofabreu.signalhub.client;

import io.quarkus.hibernate.orm.panache.PanacheRepositoryBase;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.persistence.LockModeType;
import java.util.Optional;
import java.util.UUID;

@ApplicationScoped
class ClientRepository implements PanacheRepositoryBase<ClientEntity, UUID> {

  /**
   * Loads the client for a change, holding its row lock until the transaction ends. Concurrent
   * changes (a revocation and a push-target update) then apply one after the other instead of one
   * overwriting the other.
   */
  Optional<ClientEntity> findForUpdate(UUID id) {
    return findByIdOptional(id, LockModeType.PESSIMISTIC_WRITE);
  }

  /**
   * Removes this push target from every other client. A push address belongs to one installation,
   * so when an app is re-registered (for example after reinstalling) the new client takes it over
   * and the old one no longer receives duplicate pushes.
   */
  void releasePushTarget(String provider, String token, UUID keptBy) {
    update(
        "pushProvider = null, pushToken = null, pushUpdatedAt = null"
            + " where pushProvider = ?1 and pushToken = ?2 and id <> ?3",
        provider,
        token,
        keptBy);
  }
}
