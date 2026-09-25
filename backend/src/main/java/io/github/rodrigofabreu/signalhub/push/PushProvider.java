package io.github.rodrigofabreu.signalhub.push;

/**
 * The boundary to one push provider, such as a mobile push service. Implementations are CDI beans
 * at the edge of the system; nothing else in SignalHub depends on a concrete provider. A provider
 * that is not configured must not be an active bean, so that SignalHub reports its clients' targets
 * as unsupported rather than failing every send.
 */
public interface PushProvider {

  /**
   * The provider name clients register push targets with, e.g. {@code fcm}. Lowercase letters,
   * digits and {@code . _ -}, like push target providers.
   */
  String name();

  /**
   * Sends one message to one target and classifies the result. Called outside any database
   * transaction. Must not throw for provider-reported failures; an unexpected exception is treated
   * as a transient failure.
   *
   * @param token the target's opaque provider token. Never log it.
   */
  PushOutcome send(String token, PushMessage message);
}
