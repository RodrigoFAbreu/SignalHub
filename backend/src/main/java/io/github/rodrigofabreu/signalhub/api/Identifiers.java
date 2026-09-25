package io.github.rodrigofabreu.signalhub.api;

/** Shared rule for machine-readable names in the API, such as producer names and event context. */
public final class Identifiers {

  public static final String PATTERN = "[A-Za-z0-9][A-Za-z0-9._:/-]*";
  public static final String MESSAGE =
      "must start with a letter or digit and contain only letters, digits and . _ : / -";

  private Identifiers() {}
}
