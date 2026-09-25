package io.github.rodrigofabreu.signalhub.push;

import jakarta.enterprise.context.ApplicationScoped;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;

/**
 * The test stand-in for a real push provider, named {@code test}. It records every push by token
 * and answers according to the token's prefix, so tests choose the outcome through the push target
 * they register: {@code invalid-} is {@link PushResult#INVALID_TARGET}, {@code fail-} is {@link
 * PushResult#FAILED}, {@code throw-} throws, anything else is {@link PushResult#DELIVERED}.
 */
@ApplicationScoped
public class RecordingPushProvider implements PushProvider {

  public static final String NAME = "test";

  private final Map<String, BlockingQueue<PushMessage>> sent = new ConcurrentHashMap<>();

  @Override
  public String name() {
    return NAME;
  }

  @Override
  public PushResult send(PushMessage message, String token) {
    queue(token).add(message);
    if (token.startsWith("invalid-")) {
      return PushResult.INVALID_TARGET;
    }
    if (token.startsWith("fail-")) {
      return PushResult.FAILED;
    }
    if (token.startsWith("throw-")) {
      throw new IllegalStateException("provider outage");
    }
    return PushResult.DELIVERED;
  }

  /**
   * Waits for the push about this event to this token; fails the test if none arrives in time.
   * Pushes about other events are skipped: events published by other tests are delivered in the
   * background to every target, this token's included.
   */
  public PushMessage await(String token, UUID eventId, Duration timeout)
      throws InterruptedException {
    var deadline = System.nanoTime() + timeout.toNanos();
    var queue = queue(token);
    while (true) {
      var message = queue.poll(deadline - System.nanoTime(), TimeUnit.NANOSECONDS);
      if (message == null) {
        throw new AssertionError("no push about event " + eventId + " within " + timeout);
      }
      if (message.eventId().equals(eventId)) {
        return message;
      }
    }
  }

  /** Pushes sent to this token and not yet awaited, without waiting. */
  public List<PushMessage> drain(String token) {
    var messages = new ArrayList<PushMessage>();
    queue(token).drainTo(messages);
    return messages;
  }

  private BlockingQueue<PushMessage> queue(String token) {
    return sent.computeIfAbsent(token, t -> new LinkedBlockingQueue<>());
  }
}
