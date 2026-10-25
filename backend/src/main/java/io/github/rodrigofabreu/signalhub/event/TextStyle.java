package io.github.rodrigofabreu.signalhub.event;

/**
 * What the typed text of a question with choices is: a {@code NOTE} written alongside the chosen
 * choice, or the answer itself, picked instead of a choice as an {@code OTHER} row.
 */
public enum TextStyle {
  NOTE,
  OTHER
}
