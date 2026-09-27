"use strict";

// The Connect page (docs/architecture.md#the-connect-page): creates a pairing with the management
// API and shows it as a QR code until it expires. The admin token lives only in this closure; it is
// never stored, and every request goes to this same origin.
(() => {
  const PAIRINGS = "/api/v1/admin/pairings";
  const QR_SIZE = 320;
  const $ = (id) => document.getElementById(id);

  let timer = null;
  let current = null;

  $("create").addEventListener("submit", async (event) => {
    event.preventDefault();
    showError(null);
    try {
      const pairing = await createPairing($("token").value.trim(), $("name").value.trim());
      show(pairing);
    } catch (e) {
      showError(e.message);
    }
  });

  $("copy-link").addEventListener("click", () => copyLink());
  $("copy-image").addEventListener("click", () => copyImage());
  $("download").addEventListener("click", () => download());

  async function createPairing(token, name) {
    let response;
    try {
      response = await fetch(PAIRINGS, {
        method: "POST",
        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        body: JSON.stringify({ name }),
        cache: "no-store",
      });
    } catch {
      throw new Error("Could not reach SignalHub.");
    }
    if (response.status === 401) throw new Error("Wrong admin token.");
    if (response.status === 404) {
      throw new Error("The management API is off: set SIGNALHUB_ADMIN_TOKEN on the server.");
    }
    if (!response.ok) throw new Error(await errorTitle(response));
    const pairing = await response.json();
    // The app pairs only from a link, and the link needs the server's public address.
    if (!pairing.uri) {
      throw new Error("No pairing link: set SIGNALHUB_PUBLIC_URL on the server to its public address.");
    }
    return pairing;
  }

  async function errorTitle(response) {
    try {
      const body = await response.json();
      const details = (body.violations || []).map((v) => v.message).join(", ");
      return details ? `${body.title}: ${details}` : body.title;
    } catch {
      return `SignalHub answered ${response.status}.`;
    }
  }

  function show(pairing) {
    current = pairing;
    $("pairing-name").textContent = pairing.name;
    $("status").textContent = "";
    $("qr-box").classList.remove("expired");
    $("expired-cover").hidden = true;
    $("link").value = pairing.uri;
    for (const id of ["copy-image", "copy-link", "download"]) $(id).disabled = false;
    draw(pairing.uri);
    $("pairing").hidden = false;
    clearInterval(timer);
    tick();
    timer = setInterval(tick, 1000);
  }

  function tick() {
    const left = Math.max(0, Date.parse(current.expiresAt) - Date.now());
    if (left === 0) {
      clearInterval(timer);
      $("countdown").textContent = "This code has expired.";
      $("status").textContent = "";
      $("qr-box").classList.add("expired");
      $("expired-cover").hidden = false;
      $("link").value = "";
      for (const id of ["copy-image", "copy-link", "download"]) $(id).disabled = true;
      return;
    }
    const minutes = Math.floor(left / 60000);
    const seconds = String(Math.floor((left % 60000) / 1000)).padStart(2, "0");
    $("countdown").textContent = `Expires in ${minutes}:${seconds}. It works once.`;
  }

  function draw(text) {
    // Type 0 picks the smallest QR version that fits; level M survives a slightly blurry photo.
    const qr = qrcode(0, "M");
    qr.addData(text);
    qr.make();
    const modules = qr.getModuleCount();
    const quiet = 4;
    const scale = Math.floor(QR_SIZE / (modules + 2 * quiet));
    const offset = Math.floor((QR_SIZE - scale * modules) / 2);
    const context = $("qr").getContext("2d");
    context.fillStyle = "#ffffff";
    context.fillRect(0, 0, QR_SIZE, QR_SIZE);
    context.fillStyle = "#000000";
    for (let row = 0; row < modules; row++) {
      for (let col = 0; col < modules; col++) {
        if (qr.isDark(row, col)) {
          context.fillRect(offset + col * scale, offset + row * scale, scale, scale);
        }
      }
    }
  }

  async function copyLink() {
    const text = $("link").value;
    try {
      await navigator.clipboard.writeText(text);
    } catch {
      // The clipboard API needs a secure context (https or localhost); selecting still works.
      $("link").select();
      if (!document.execCommand("copy")) {
        return status("Copy the selected link with Ctrl+C.");
      }
    }
    status("Link copied.");
  }

  async function copyImage() {
    if (!navigator.clipboard || typeof ClipboardItem === "undefined") {
      return status("This browser cannot copy images here. Use Download QR.");
    }
    try {
      await navigator.clipboard.write([new ClipboardItem({ "image/png": pngBlob() })]);
      status("QR image copied.");
    } catch {
      status("Could not copy the image. Use Download QR.");
    }
  }

  function pngBlob() {
    return new Promise((resolve, reject) =>
      $("qr").toBlob((blob) => (blob ? resolve(blob) : reject(new Error("no image"))), "image/png"),
    );
  }

  async function download() {
    const url = URL.createObjectURL(await pngBlob());
    const link = document.createElement("a");
    link.href = url;
    link.download = `signalhub-pairing-${current.name.replace(/[^\w.-]+/g, "_")}.png`;
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  function status(text) {
    $("status").textContent = text;
  }

  function showError(text) {
    $("error").textContent = text || "";
    $("error").hidden = !text;
  }
})();
