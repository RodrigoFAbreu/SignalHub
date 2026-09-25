package io.github.rodrigofabreu.signalhub.event;

import java.util.UUID;

/** Fired when an event is stored; observers that run after the commit may rely on it existing. */
record EventStored(UUID eventId) {}
