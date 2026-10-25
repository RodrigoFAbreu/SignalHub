package io.github.rodrigofabreu.signalhub.event;

import io.quarkus.runtime.ShutdownEvent;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import jakarta.transaction.Status;
import jakarta.transaction.Synchronization;
import jakarta.transaction.TransactionSynchronizationRegistry;
import java.time.Duration;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Semaphore;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Wakes the producers whose read of an answer is held open ({@code GET /events/{id}/answer?wait=}).
 * In process, as SignalHub runs as one backend: a change is announced once it has committed, so a
 * woken request that re-reads sees it. A waiter registers before it reads the state, so no change
 * between the read and the wait is missed. Any deletion wakes every waiter, whatever event it
 * deleted, and shutdown does too.
 */
@ApplicationScoped
class QuestionWakeups {

  /** At most this many reads wait at once; beyond it a read answers with the state at once. */
  static final int MAX_WAITS = 200;

  /**
   * One held read, which keeps its place across wake-ups: woken when its event changes, any event
   * is deleted, or the backend stops. A wake-up that comes before the read waits is not lost.
   */
  static final class Waiter {
    private final UUID eventId;
    private final Semaphore woken = new Semaphore(0);

    private Waiter(UUID eventId) {
      this.eventId = eventId;
    }

    private void wake() {
      woken.release();
    }

    /** Forgets wake-ups so far; call it just before reading the state the wake-ups are about. */
    void clear() {
      woken.drainPermits();
    }

    /** Waits for a wake-up; true if woken, false if the time passed first. */
    boolean await(Duration timeout) throws InterruptedException {
      return woken.tryAcquire(Math.max(timeout.toNanos(), 0), TimeUnit.NANOSECONDS);
    }
  }

  private final TransactionSynchronizationRegistry transactions;
  private final Set<Waiter> waiters = ConcurrentHashMap.newKeySet();
  private final AtomicInteger waiting = new AtomicInteger();
  private volatile boolean shuttingDown;

  QuestionWakeups(TransactionSynchronizationRegistry transactions) {
    this.transactions = transactions;
  }

  /** Reserves one of the {@link #MAX_WAITS} places; null if all are taken or the backend stops. */
  Waiter register(UUID eventId) {
    if (shuttingDown || waiting.incrementAndGet() > MAX_WAITS) {
      waiting.decrementAndGet();
      return null;
    }
    var waiter = new Waiter(eventId);
    waiters.add(waiter);
    return waiter;
  }

  void unregister(Waiter waiter) {
    if (waiters.remove(waiter)) {
      waiting.decrementAndGet();
    }
  }

  boolean shuttingDown() {
    return shuttingDown;
  }

  /** Wakes the reads waiting for this event once the current transaction commits. */
  void changedAfterCommit(UUID eventId) {
    afterCommit(
        () -> waiters.stream().filter(w -> w.eventId.equals(eventId)).forEach(Waiter::wake));
  }

  /** Wakes every waiting read once the current transaction commits: some event was deleted. */
  void deletedAfterCommit() {
    afterCommit(() -> waiters.forEach(Waiter::wake));
  }

  void onStop(@Observes ShutdownEvent event) {
    shuttingDown = true;
    waiters.forEach(Waiter::wake);
  }

  private void afterCommit(Runnable wake) {
    if (transactions.getTransactionStatus() != Status.STATUS_ACTIVE) {
      wake.run();
      return;
    }
    transactions.registerInterposedSynchronization(
        new Synchronization() {
          @Override
          public void beforeCompletion() {
            // Nothing to prepare.
          }

          @Override
          public void afterCompletion(int status) {
            if (status == Status.STATUS_COMMITTED) {
              wake.run();
            }
          }
        });
  }
}
