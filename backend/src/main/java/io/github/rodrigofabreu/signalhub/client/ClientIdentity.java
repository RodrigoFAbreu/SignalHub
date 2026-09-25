package io.github.rodrigofabreu.signalhub.client;

import java.util.UUID;

/** Who a client is: its canonical ID and its name. */
public record ClientIdentity(UUID id, String name) {}
