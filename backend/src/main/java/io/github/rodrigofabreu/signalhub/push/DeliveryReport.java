package io.github.rodrigofabreu.signalhub.push;

import java.util.Objects;

/**
 * What {@link PushDelivery} reports for one push to one client: the result, and a short reason when
 * there is one (the provider's, for a failure). The reason is shown to the operator, so, like
 * {@link PushOutcome#detail()}, it never contains the push token or credentials.
 */
public record DeliveryReport(DeliveryResult result, String detail) {

  public DeliveryReport {
    Objects.requireNonNull(result, "result");
    detail = detail == null ? "" : detail;
  }

  static DeliveryReport of(DeliveryResult result) {
    return new DeliveryReport(result, "");
  }
}
