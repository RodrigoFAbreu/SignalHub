package io.github.rodrigofabreu.signalhub.event;

import java.util.UUID;

/** A stored event waiting for its push: only the generic fields a push is built from. */
record PendingPush(UUID eventId, String title, String message) {}
