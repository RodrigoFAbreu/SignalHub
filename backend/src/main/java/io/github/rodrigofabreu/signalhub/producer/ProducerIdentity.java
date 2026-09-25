package io.github.rodrigofabreu.signalhub.producer;

import java.util.UUID;

/** Who a producer is: its canonical ID and its name. */
public record ProducerIdentity(UUID id, String name) {}
