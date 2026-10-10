// The words for a change that did not work: what happened and what to do, never the server's own
// title and never blaming the person.

import { ApiError } from "./api.js";

/** The sentence for a failed change; `doing` completes "Couldn't …", such as `rename ana-reports`. */
export function failureMessage(error, doing) {
  if (error instanceof ApiError) {
    if (error.offline) return `Couldn't ${doing}. Check your connection and try again.`;
    if (error.status >= 500) return "SignalHub had a problem. Try again in a moment.";
    if (error.status === 403) return "Your role doesn't allow this. It may have changed.";
  }
  return `Couldn't ${doing}. Try again.`;
}

/** A failure whose message is already shown elsewhere (a field's error): the dialog adds none. */
export function silent(message = "") {
  const error = new Error(message);
  error.silent = true;
  return error;
}

export const NameMessages = {
  taken: "That name is taken. Names are shared by everyone on this server.",
  notAllowed: "Use letters, numbers and . _ : / - only, starting with a letter or number.",
  empty: "Give it a name.",
  tooLong: "Use 100 characters or fewer.",
  help: "Letters, numbers and . _ : / - only, starting with a letter or number. Others see this name.",
};

const NAME = /^[A-Za-z0-9][A-Za-z0-9._:/-]*$/;

/** The problem with a producer's name as typed, or null. Mirrors the server's rule. */
export function nameProblem(name) {
  if (!name) return NameMessages.empty;
  if (!NAME.test(name)) return NameMessages.notAllowed;
  if (name.length > 100) return NameMessages.tooLong;
  return null;
}
