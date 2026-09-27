package io.github.rodrigofabreu.signalhub.client;

import java.util.UUID;

/**
 * Fired, as a CDI event, once a device has redeemed a pairing code and its client is committed, so
 * the owner's other devices can be told. {@code byClientId} and {@code byName} are the admin device
 * that created the code, or null if the operator did. Never carries the code or the key.
 */
public record ClientPaired(
    UUID clientId, String name, boolean admin, UUID byClientId, String byName) {}
