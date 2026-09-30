package io.github.rodrigofabreu.signalhub.event;

import java.util.List;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/**
 * Response of {@code GET /api/v1/admin/status}: what the admin page's status panel needs that is
 * otherwise only in the metrics or the configuration. Never a secret, a key or a push token.
 */
@Schema(
    name = "ServiceStatus",
    description =
        "Push configuration, the push backlog and the retention setting, for the operator. The"
            + " release is at /q/info, health at /q/health, devices' last push results in the"
            + " client list and the latest event in the event listing.")
public record ServiceStatus(
    @Schema(
            required = true,
            description =
                "The push providers enabled, by name, such as fcm; empty when no push provider"
                    + " is configured and nothing is pushed.",
            examples = "[\"fcm\"]")
        List<String> pushProviders,
    @Schema(
            description =
                "The provider whose push options apps are given (/api/v1/client/push-config);"
                    + " null when none are served and apps need options built in.",
            examples = "fcm")
        String pushClientOptions,
    @Schema(
            required = true,
            description = "Events whose push is not dispatched yet.",
            examples = "0")
        long pendingDispatches,
    @Schema(
            required = true,
            description =
                "Pushes to one client that failed temporarily and wait to be sent again, due or"
                    + " not.",
            examples = "0")
        long pendingRetries,
    @Schema(
            required = true,
            description =
                "Pushes to one client given up after the last attempt failed temporarily, since"
                    + " the backend started.",
            examples = "0")
        long abandonedRetries,
    @Schema(
            description =
                "How long events are kept, in seconds (SIGNALHUB_EVENTS_RETENTION); null when"
                    + " they are kept forever.",
            examples = "31536000")
        Long eventRetentionSeconds) {

  public ServiceStatus {
    pushProviders = List.copyOf(pushProviders);
  }
}
