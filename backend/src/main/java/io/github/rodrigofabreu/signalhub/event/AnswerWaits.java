package io.github.rodrigofabreu.signalhub.event;

import io.github.rodrigofabreu.signalhub.api.QuestionState;
import jakarta.enterprise.context.ApplicationScoped;
import java.time.Duration;
import java.time.Instant;
import java.util.UUID;

/**
 * The producer's held read of an answer: returns the question's state as soon as it leaves {@code
 * OPEN}, or when the wait ends. It holds no transaction or connection while it waits (each read is
 * its own short transaction), so it runs on a virtual thread, and a wait takes one of {@link
 * QuestionWakeups#MAX_WAITS} places; without one, it answers at once with the current state.
 */
@ApplicationScoped
class AnswerWaits {

  static final int MAX_WAIT_SECONDS = 60;

  private final QuestionService questions;
  private final QuestionWakeups wakeups;

  AnswerWaits(QuestionService questions, QuestionWakeups wakeups) {
    this.questions = questions;
    this.wakeups = wakeups;
  }

  QuestionService.Reading read(UUID eventId, UUID producerId, int waitSeconds) {
    var waiter = waitSeconds > 0 ? wakeups.register(eventId) : null;
    if (waiter == null) {
      return questions.read(eventId, producerId);
    }
    try {
      return hold(eventId, producerId, waiter, Instant.now().plusSeconds(waitSeconds));
    } finally {
      wakeups.unregister(waiter);
    }
  }

  private QuestionService.Reading hold(
      UUID eventId, UUID producerId, QuestionWakeups.Waiter waiter, Instant until) {
    QuestionService.Reading reading = null;
    while (true) {
      // At shutdown the database may already be closing: answer with the state last read.
      if (reading != null && wakeups.shuttingDown()) {
        return reading;
      }
      // Cleared before the read: a change after it leaves a wake-up that ends the next wait.
      waiter.clear();
      reading = questions.read(eventId, producerId);
      if (!(reading instanceof QuestionService.Reading.Found found)
          || found.state().state() != QuestionState.State.OPEN) {
        return reading;
      }
      var now = Instant.now();
      var stop =
          found.closesAt() != null && found.closesAt().isBefore(until) ? found.closesAt() : until;
      if (!now.isBefore(until)) {
        return reading;
      }
      try {
        // A moment past closesAt, so the read after it sees the question closed by time.
        waiter.await(Duration.between(now, stop).plusMillis(2));
      } catch (InterruptedException e) {
        Thread.currentThread().interrupt();
        return reading;
      }
    }
  }
}
