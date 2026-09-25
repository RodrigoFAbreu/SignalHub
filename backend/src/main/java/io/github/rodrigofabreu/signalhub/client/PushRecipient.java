package io.github.rodrigofabreu.signalhub.client;

import java.util.UUID;

/** A client that has a push target, with the preferences that decide which events it gets. */
public record PushRecipient(UUID clientId, PushPreferences preferences) {}
