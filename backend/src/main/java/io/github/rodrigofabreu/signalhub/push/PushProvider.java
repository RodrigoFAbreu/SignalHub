package io.github.rodrigofabreu.signalhub.push;

/**
 * A push provider's transport, the only place that knows its protocol and credentials. An
 * implementation is a CDI bean; delivery uses it for push targets whose provider name equals {@link
 * #name()}. A provider that needs configuration it does not have must not be a bean, so it is never
 * offered targets it cannot serve.
 */
public interface PushProvider {

  /**
   * The provider name that clients use in their push target, such as {@code fcm}. Follows the push
   * target rule: lowercase letters, digits and {@code . _ -}, starting with a letter or digit.
   */
  String name();

  /**
   * Sends one push to one installation. May block on network I/O; delivery runs off the request
   * thread. Should report failures as a result rather than throw; an exception counts as {@link
   * PushResult#FAILED}.
   *
   * @param token the opaque address the provider issued to the installation; never log it
   */
  PushResult send(PushMessage message, String token);
}
