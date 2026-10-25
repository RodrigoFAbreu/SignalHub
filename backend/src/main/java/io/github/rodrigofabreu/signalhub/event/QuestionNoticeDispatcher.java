package io.github.rodrigofabreu.signalhub.event;

import io.github.rodrigofabreu.signalhub.push.PushDelivery;
import io.github.rodrigofabreu.signalhub.push.PushMessage;
import io.quarkus.scheduler.Scheduled;
import jakarta.enterprise.context.ApplicationScoped;
import java.util.Map;
import org.jboss.logging.Logger;

/**
 * Sends the {@link PushNotices}: a data-only push, {@code notice=answered|closed|deleted} with the
 * {@code eventId}, to each device that was shown the event, so the app removes its notification.
 * Each notice is sent once and deleted, without a retry per device and without delivery records: a
 * device that misses it keeps a card that opens the event, which shows the question's current
 * state.
 */
@ApplicationScoped
class QuestionNoticeDispatcher {

  private static final Logger LOG = Logger.getLogger(QuestionNoticeDispatcher.class);

  private final PushNotices notices;
  private final PushDelivery delivery;

  QuestionNoticeDispatcher(PushNotices notices, PushDelivery delivery) {
    this.notices = notices;
    this.delivery = delivery;
  }

  @Scheduled(
      identity = "question-notices",
      every = "${signalhub.push.dispatch.interval:2s}",
      concurrentExecution = Scheduled.ConcurrentExecution.SKIP)
  void run() {
    sendDue();
  }

  /** Sends every due notice; returns how many were sent. */
  int sendDue() {
    var sent = 0;
    for (var next = notices.claimNext(EventPushDispatcher.LEASE);
        next.isPresent();
        next = notices.claimNext(EventPushDispatcher.LEASE)) {
      var notice = next.get();
      try {
        var message =
            PushMessage.dataOnly(
                Map.of("notice", notice.notice(), "eventId", notice.eventId().toString()));
        for (var clientId : notice.clientIds()) {
          delivery.deliver(clientId, message);
        }
        notices.complete(notice.id());
        sent++;
      } catch (RuntimeException e) {
        // The claim expires and the notice is sent again; carry on with the others.
        LOG.warnf(
            "Sending the %s notice of event %s failed: %s",
            notice.notice(), notice.eventId(), e.getClass().getName());
      }
    }
    return sent;
  }
}
