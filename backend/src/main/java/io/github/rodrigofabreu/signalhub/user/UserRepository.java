package io.github.rodrigofabreu.signalhub.user;

import io.quarkus.hibernate.orm.panache.PanacheRepositoryBase;
import io.quarkus.panache.common.Sort;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.persistence.LockModeType;
import java.util.Optional;
import java.util.UUID;

@ApplicationScoped
class UserRepository implements PanacheRepositoryBase<UserEntity, UUID> {

  /** Holds the user's row lock until the transaction ends, so changes to one user apply in turn. */
  Optional<UserEntity> findForUpdate(UUID id) {
    return findByIdOptional(id, LockModeType.PESSIMISTIC_WRITE);
  }

  /** Whether another user has this name, ignoring case, as the unique index does. */
  boolean nameTaken(String name, UUID except) {
    return count("lower(name) = lower(?1) and id <> ?2", name, except) > 0;
  }

  /** The oldest user who is an admin and not revoked: the owner of the instance. */
  Optional<UserEntity> oldestActiveAdmin() {
    return find("role = ?1 and revokedAt is null", Sort.by("createdAt").and("id"), Role.ADMIN)
        .firstResultOptional();
  }
}
