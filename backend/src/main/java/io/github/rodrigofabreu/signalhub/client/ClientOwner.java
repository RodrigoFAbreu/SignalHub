package io.github.rodrigofabreu.signalhub.client;

import java.util.UUID;

/** A client and the user it belongs to. */
public record ClientOwner(UUID clientId, UUID userId) {}
