package io.github.rodrigofabreu.signalhub.push;

import jakarta.enterprise.context.ApplicationScoped;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.function.BiFunction;

/**
 * A push provider for tests, named {@code fake}: records every send and answers what the test
 * scripts. Lives only on the test classpath, so no real provider or credential is ever needed.
 */
@ApplicationScoped
public class FakePushProvider implements PushProvider {

  public static final String NAME = "fake";

  /** One recorded send. */
  public record Sent(String token, PushMessage message) {}

  private final List<Sent> sent = new CopyOnWriteArrayList<>();
  private volatile BiFunction<String, PushMessage, PushOutcome> behaviour =
      (token, message) -> PushOutcome.delivered();

  @Override
  public String name() {
    return NAME;
  }

  @Override
  public PushOutcome send(String token, PushMessage message) {
    sent.add(new Sent(token, message));
    return behaviour.apply(token, message);
  }

  /** Scripts the answer to every following send, and forgets earlier sends. */
  public void answer(BiFunction<String, PushMessage, PushOutcome> behaviour) {
    this.behaviour = behaviour;
    sent.clear();
  }

  public List<Sent> sent() {
    return List.copyOf(sent);
  }
}
