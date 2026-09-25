package io.github.rodrigofabreu.signalhub.producer;

import static java.lang.annotation.ElementType.METHOD;
import static java.lang.annotation.ElementType.TYPE;
import static java.lang.annotation.RetentionPolicy.RUNTIME;

import jakarta.ws.rs.NameBinding;
import java.lang.annotation.Retention;
import java.lang.annotation.Target;

/** Requires the operator's admin token ({@code Authorization: Bearer <token>}). */
@NameBinding
@Target({TYPE, METHOD})
@Retention(RUNTIME)
@interface AdminOnly {}
