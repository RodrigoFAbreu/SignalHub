package io.github.rodrigofabreu.signalhub.producer;

/** Who disabled a producer, as the admin API reports it. */
public enum DisabledBy {
  /** Its owner, from a device. Only an admin can enable it again if the operator disabled it. */
  OWNER,
  /** The operator with the admin token, or the revoking of its owner. */
  ADMIN
}
