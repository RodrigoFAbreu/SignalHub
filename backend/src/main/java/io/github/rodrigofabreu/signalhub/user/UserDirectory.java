package io.github.rodrigofabreu.signalhub.user;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.transaction.Transactional;
import java.util.Collection;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * Read-only lookups of users, for the packages whose rows belong to a user (clients, producers,
 * events). Depends on nothing else, so any of them may use it.
 */
@ApplicationScoped
public class UserDirectory {

  private final UserRepository users;

  UserDirectory(UserRepository users) {
    this.users = users;
  }

  /** Any user, revoked or not. */
  @Transactional
  public Optional<UserRef> find(UUID id) {
    return users.findByIdOptional(id).map(UserEntity::ref);
  }

  /** Whether the user exists and is not revoked. */
  @Transactional
  public boolean isActive(UUID id) {
    return users.findByIdOptional(id).map(user -> !user.revoked()).orElse(false);
  }

  /**
   * The user if they exist and are not revoked, holding their row lock until the transaction ends.
   * Revoking a user takes the same lock first, so a device cannot be paired for a user who is being
   * revoked, and a user's devices are changed one at a time. Take it before any client row's lock.
   */
  @Transactional
  public Optional<UserRef> lockActive(UUID id) {
    return users.findForUpdate(id).filter(user -> !user.revoked()).map(UserEntity::ref);
  }

  /** The given users by ID, revoked or not. One query whatever the number of IDs. */
  @Transactional
  public Map<UUID, UserRef> find(Collection<UUID> ids) {
    if (ids.isEmpty()) {
      return Map.of();
    }
    return users.list("id in ?1", ids).stream()
        .collect(Collectors.toMap(UserEntity::id, UserEntity::ref));
  }

  /** The users who are not revoked, by name ignoring case. */
  @Transactional
  public List<UserRef> active() {
    return users.list("revokedAt is null").stream()
        .map(UserEntity::ref)
        .sorted(Comparator.comparing(UserRef::name, String.CASE_INSENSITIVE_ORDER))
        .toList();
  }

  /**
   * The user the management API acts for when a request names none: the oldest admin who is not
   * revoked, the owner of the instance. Empty if there is none.
   */
  @Transactional
  public Optional<UserRef> defaultOwner() {
    return users.oldestActiveAdmin().map(UserEntity::ref);
  }
}
