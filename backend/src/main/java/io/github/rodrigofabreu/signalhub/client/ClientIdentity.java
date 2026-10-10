package io.github.rodrigofabreu.signalhub.client;

import io.github.rodrigofabreu.signalhub.user.Role;
import java.util.UUID;

/**
 * Who a client is: its canonical ID and name, and the user it belongs to with that user's role,
 * read when the key authenticated.
 */
public record ClientIdentity(UUID id, String name, UUID userId, Role role) {}
