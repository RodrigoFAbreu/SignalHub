package io.github.rodrigofabreu.signalhub.client;

/**
 * What a client is: a {@code DEVICE} (an app installation, a script) authenticates with a key it
 * holds; a {@code BROWSER} is signed in from a device of the user and authenticates with a key held
 * only in an HttpOnly cookie, for a fixed time.
 */
public enum ClientKind {
  DEVICE,
  BROWSER
}
