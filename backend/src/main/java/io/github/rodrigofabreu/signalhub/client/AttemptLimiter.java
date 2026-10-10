package io.github.rodrigofabreu.signalhub.client;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayDeque;
import java.util.HashMap;
import java.util.Map;

/**
 * Bounds failed tries: at most {@code max} within {@code window} per key. Kept in memory because
 * SignalHub is one service, and a restart only forgives a few tries. Succeeding does not reset it,
 * so a device cannot interleave a right guess to keep guessing.
 */
final class AttemptLimiter<K> {

  private final int max;
  private final Duration window;
  private final Map<K, ArrayDeque<Instant>> failures = new HashMap<>();

  AttemptLimiter(int max, Duration window) {
    this.max = max;
    this.window = window;
  }

  /** Whether the key has used up its tries. */
  synchronized boolean blocked(K key, Instant now) {
    return recent(key, now).size() >= max;
  }

  synchronized void fail(K key, Instant now) {
    recent(key, now).addLast(now);
  }

  private ArrayDeque<Instant> recent(K key, Instant now) {
    var times = failures.computeIfAbsent(key, k -> new ArrayDeque<>());
    var from = now.minus(window);
    while (!times.isEmpty() && !times.peekFirst().isAfter(from)) {
      times.removeFirst();
    }
    if (times.isEmpty() && failures.size() > 10_000) {
      failures.values().removeIf(ArrayDeque::isEmpty);
    }
    return times;
  }
}
