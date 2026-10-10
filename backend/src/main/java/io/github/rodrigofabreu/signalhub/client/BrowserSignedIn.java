package io.github.rodrigofabreu.signalhub.client;

import java.util.UUID;

/**
 * Fired, as a CDI event, once a browser's sign-in is committed, so the devices that should know can
 * be told: those of {@code userId}, whose browser it now is, and of the admins. {@code byClientId}
 * and {@code byName} are the device that approved it. Never carries a key.
 */
public record BrowserSignedIn(
    UUID clientId, String name, UUID userId, UUID byClientId, String byName) {}
