package io.github.rodrigofabreu.signalhub;

import java.time.Duration;
import java.time.Instant;

/**
 * When a client's or a producer key's "last used" time is worth writing again. Recording it on
 * every request would add a database write to each one, event ingestion included, so a time is
 * rewritten only once it is {@link #INTERVAL} old: what is shown may be that much behind.
 */
public final class LastUsed {

  /** The longest a recorded time may lag behind the real last use. */
  public static final Duration INTERVAL = Duration.ofMinutes(1);

  private LastUsed() {}

  /** Whether {@code recorded} (null if never) is old enough to be replaced by {@code now}. */
  public static boolean due(Instant recorded, Instant now) {
    return recorded == null || !recorded.plus(INTERVAL).isAfter(now);
  }
}
