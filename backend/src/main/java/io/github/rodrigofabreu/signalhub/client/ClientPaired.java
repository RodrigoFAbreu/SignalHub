package io.github.rodrigofabreu.signalhub.client;

import java.util.UUID;

/**
 * Fired, as a CDI event, once a device has redeemed a pairing code and its client is committed, so
 * the owner's other devices can be told. Never carries the code or the key.
 */
public record ClientPaired(UUID clientId, String name) {}
