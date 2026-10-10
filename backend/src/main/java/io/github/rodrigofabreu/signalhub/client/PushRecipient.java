package io.github.rodrigofabreu.signalhub.client;

import java.util.UUID;

/**
 * A client that has a push target, with its user (and whether they are an admin) and the
 * preferences that decide which events it gets.
 */
public record PushRecipient(
    UUID clientId, UUID userId, boolean userIsAdmin, PushPreferences preferences) {}
