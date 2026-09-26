package io.github.rodrigofabreu.signalhub.push;

import java.util.Map;

/**
 * The options a client app needs to set up one push provider on the device, such as the identifiers
 * of the operator's project with that provider. They are served to authenticated clients as they
 * are, so an implementation must hold only client-safe values, never a credential able to send
 * pushes. Implementations are CDI beans at the edge of the system and, like {@link PushProvider}s,
 * are active only when configured.
 */
public interface PushClientOptions {

  /** The push provider the options are for; it must be an active {@link PushProvider}. */
  String provider();

  /** Option names and values, opaque to SignalHub. */
  Map<String, String> options();
}
