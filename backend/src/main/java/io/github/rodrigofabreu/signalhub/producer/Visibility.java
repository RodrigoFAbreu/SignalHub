package io.github.rodrigofabreu.signalhub.producer;

/** Who sees a producer, and so may subscribe to it. */
public enum Visibility {
  /** Every user on the server may see it and subscribe, without approval. */
  PUBLIC,
  /** Its owner and the users on its allow-list. */
  PRIVATE
}
