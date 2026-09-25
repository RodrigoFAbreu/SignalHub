package io.github.rodrigofabreu.signalhub.event;

import java.util.UUID;

/** A claimed {@code push_retries} row: a push to one client that failed temporarily. */
record PushRetry(UUID eventId, UUID clientId, int attempts) {}
