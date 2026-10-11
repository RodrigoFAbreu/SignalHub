// The sign-in screen, the only one without the rail: one field for the admin token, one button.
// There are no accounts and no passwords: the token is the server's SIGNALHUB_ADMIN_TOKEN, checked
// against the management API and kept in this page's memory only (see api.js).

import { ApiError, signIn } from "./api.js";
import { el, icon } from "./dom.js";
import { parseHash } from "./router.js";
import { spinner } from "./ui.js";

const MIN_LENGTH = 32;
const HELP = "The token stays in this page only. It is not saved in the browser and goes nowhere but this server; reloading or closing the tab asks again.";
const SECTION_NAMES = { devices: "Devices", users: "Users", producers: "Producers", events: "Events", status: "Status" };

/**
 * Shows the screen in `root` until the token is accepted, then resolves. `reason` is `first`,
 * `signedOut` (the operator signed out) or `lost` (the token stopped working while in use).
 */
export function requestSignIn(root, reason) {
  return new Promise((resolve) => {
    let typed = "";
    let shown = false;
    let phase = reason; // first | signedOut | lost, then busy | wrong | off | unreachable | answered
    let failure = null;
    let focusField = true;

    const render = () => {
      const off = phase === "off";
      const busy = phase === "busy";
      const input = el("input", {
        id: "admin-token",
        name: "admin-token",
        type: shown ? "text" : "password",
        autocomplete: "current-password",
        spellcheck: "false",
        autocapitalize: "off",
        required: true,
        disabled: off || busy,
        "aria-describedby": "token-help",
        "aria-invalid": phase === "wrong" ? "true" : null,
      });
      input.value = typed;
      const toggle = el(
        "button",
        {
          type: "button",
          class: "vis",
          "aria-label": shown ? "Hide the token" : "Show the token",
          "aria-pressed": String(shown),
          disabled: off || busy,
          on: {
            click: () => {
              shown = !shown;
              input.type = shown ? "text" : "password";
              toggle.setAttribute("aria-label", shown ? "Hide the token" : "Show the token");
              toggle.setAttribute("aria-pressed", String(shown));
              toggle.replaceChildren(icon(shown ? "visibility_off" : "visibility"));
              input.focus();
            },
          },
        },
        icon(shown ? "visibility_off" : "visibility"),
      );
      const box = el(
        "div",
        { class: `tf${phase === "wrong" ? " err" : ""}${off || busy ? " dis" : ""}` },
        input,
        el("label", { class: "fl", for: "admin-token", text: "Admin token" }),
        phase === "wrong" ? icon("error", "tf-err") : null,
        toggle,
      );
      const short = typed.length > 0 && typed.length < MIN_LENGTH;
      const help = el("div", { class: `help${phase === "wrong" ? " err" : ""}`, id: "token-help" });
      if (phase === "wrong") {
        help.setAttribute("role", "alert");
        help.textContent = "Wrong admin token";
      } else if (busy) {
        help.textContent = "Checking the token with the server…";
      } else if (!off) {
        help.textContent = `${short ? `At least ${MIN_LENGTH} characters; this one has ${typed.length}. ` : ""}${HELP}`;
      }

      const submit = el(
        "button",
        {
          type: "submit",
          class: `btn-f go${busy ? " busy" : ""}`,
          disabled: off || busy || typed.length < MIN_LENGTH,
          "aria-busy": busy ? "true" : null,
        },
        busy ? spinner() : null,
        el("span", { text: busy ? "Signing in…" : phase === "unreachable" || phase === "answered" ? "Try again" : "Sign in" }),
      );
      const actions = el("div", { class: "acts" }, submit);
      if (off) {
        actions.append(
          el("button", { type: "button", class: "btn-o go", on: { click: () => location.reload() } }, icon("refresh"), el("span", { text: "Reload this page" })),
        );
      }

      const card = el("form", { class: `sic${off ? " w520" : phase === "lost" ? " w480" : ""}`, autocomplete: "on", "aria-labelledby": "signin-title", novalidate: true });
      card.append(el("span", { class: "rlogo" }, icon("sensors")), el("h1", { id: "signin-title", text: "SignalHub admin" }));
      const message = notice(phase, failure);
      if (message) card.append(message);
      else if (phase !== "wrong") {
        card.append(
          el("p", {
            text: "The operator's page: people, devices, producers and events, and whether SignalHub is working. It is served only on this server's own port, never through the public address.",
          }),
        );
      }
      if (off) {
        card.append(el("div", { class: "tf dis" }, el("span", { class: "fl", text: "Admin token" }), el("span", { class: "c-var", text: "Not available" })));
      } else {
        card.append(box, help);
      }
      if (phase === "wrong") {
        card.append(
          el("p", {
            class: "after",
            text: "SignalHub did not accept it. Check it against SIGNALHUB_ADMIN_TOKEN in the server's .env: capital letters count and there must be no space at either end.",
          }),
        );
      }
      if (phase === "lost") {
        const where = SECTION_NAMES[parseHash().section];
        card.append(el("div", { class: "ret" }, icon("undo", "ms18"), el("span", { text: `You will come back to the ${where} section, where you were.` })));
      }
      card.append(actions);
      card.addEventListener("submit", (event) => {
        event.preventDefault();
        attempt();
      });
      input.addEventListener("input", () => {
        typed = input.value;
        // Typing replaces what was said about the last try.
        if (phase === "wrong" || phase === "unreachable" || phase === "answered") {
          phase = reason === "lost" || reason === "signedOut" ? reason : "first";
          failure = null;
          focusField = true;
          render();
          return;
        }
        submit.disabled = typed.length < MIN_LENGTH;
        const nowShort = typed.length > 0 && typed.length < MIN_LENGTH;
        help.textContent = `${nowShort ? `At least ${MIN_LENGTH} characters; this one has ${typed.length}. ` : ""}${HELP}`;
      });
      root.replaceChildren(el("div", { class: "si" }, card));
      if (focusField && !off && !busy) input.focus();
      else if (off) card.querySelector("button.btn-o")?.focus();
    };

    async function attempt() {
      if (typed.length < MIN_LENGTH || phase === "busy") return;
      phase = "busy";
      render();
      try {
        await signIn(typed);
        typed = "";
        root.replaceChildren();
        resolve();
      } catch (error) {
        const kind = error instanceof ApiError ? error.kind : "unreachable";
        phase = kind === "wrong" || kind === "off" || kind === "answered" ? kind : "unreachable";
        failure = error;
        focusField = true;
        render();
      }
    }

    render();
  });
}

/** The notice above the field, for the states that have one. */
function notice(phase, failure) {
  if (phase === "off") {
    return el(
      "div",
      { class: "bn neu", role: "alert" },
      icon("block"),
      el(
        "div",
        { class: "tx" },
        el("b", { text: "The admin page is switched off on this server.", class: "lead-b" }),
        el("br"),
        "The server has no admin token set, so nobody can sign in. To switch it on:",
        el(
          "ol",
          { class: "steps" },
          el("li", {}, "Set SIGNALHUB_ADMIN_TOKEN in the server's .env to a secret of at least 32 characters (for example from ", el("span", { class: "mono", text: "openssl rand -hex 32" }), ")."),
          el("li", { text: "Restart SignalHub." }),
          el("li", { text: "Reload this page." }),
        ),
      ),
    );
  }
  if (phase === "unreachable") {
    return el(
      "div",
      { class: "bn err", role: "alert" },
      icon("cloud_off"),
      el(
        "div",
        { class: "tx" },
        el("b", { text: "Could not reach SignalHub.", class: "lead-b" }),
        el("br"),
        "The server did not answer. Check that it is running (",
        el("span", { class: "mono", text: "docker compose ps" }),
        ") and that this address is the server's own port, then try again.",
      ),
    );
  }
  if (phase === "answered") {
    return el(
      "div",
      { class: "bn err", role: "alert" },
      icon("cloud_off"),
      el("div", { class: "tx" }, el("b", { text: failure?.message ?? "SignalHub did not answer.", class: "lead-b" }), el("br"), "Try again; if it stays, read the server's log."),
    );
  }
  if (phase === "signedOut") {
    return el(
      "div",
      { class: "bn neu", role: "status" },
      icon("check_circle", "c-primary"),
      el("div", { class: "tx" }, el("b", { text: "You signed out.", class: "lead-b" }), el("br"), "This page forgot the token. Nothing else changed on the server."),
    );
  }
  if (phase === "lost") {
    return el(
      "div",
      { class: "bn neu", role: "alert" },
      icon("lock_clock", "c-primary"),
      el(
        "div",
        { class: "tx" },
        el("b", { text: "Your session ended.", class: "lead-b" }),
        el("br"),
        "The token stopped working while you were using the page: it was changed on the server, or the server now has a different one. Sign in again with the current token.",
      ),
    );
  }
  return null;
}
