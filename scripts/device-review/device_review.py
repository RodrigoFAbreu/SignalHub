"""Functional review of the SignalHub Android app on a real device, over adb.

Review tooling, not product code: it drives a debug build that is already set
up with a client key, publishes events as a producer, and checks what the
phone and the server show. Every value specific to one machine or device
comes from the environment or the command line; keys are read from files.
See README.md in this directory for the prerequisites and what each check
does and changes.

    python scripts/device-review/device_review.py --list
    python scripts/device-review/device_review.py [--check NAME ...]
"""

from __future__ import annotations

import argparse
import http.client
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid
from collections.abc import Callable
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from xml.etree import ElementTree

APP_PACKAGE = "io.github.rodrigofabreu.signalhub"
APP_ACTIVITY = f"{APP_PACKAGE}/.MainActivity"
EVENTS_CHANNEL = "events"
IMPORTANCE_HIGH = 4
# The windows the system shade has had across Android versions.
SHADE_WINDOWS = frozenset({"NotificationShade", "StatusBar"})
# The texts the app shows, from client/lib/src (a reference for finding
# elements on the screen, not a contract).
PUSH_ON = "Push notifications are on"
MENU = "Show menu"
DEVICE_ITEM = "This device"
NOTIFICATIONS_ITEM = "Notifications"
PUSH_SWITCH = "Push notifications"
MARK_READ = "Mark as read"
MARK_UNREAD = "Mark as unread"
EVENT_SCREEN_TITLE = "Event"

PUSH_WAIT = 90.0
QUIET_WAIT = 20.0
# The level field of a log line, in the text format or as JSON.
LOG_PROBLEM = re.compile(
    r"\s(?:WARN|ERROR|FATAL)\s+\[|\"level\"\s*:\s*\"(?:WARN|WARNING|ERROR|SEVERE|FATAL)\""
)


class GuardError(Exception):
    """The screen may not be touched: the run stops."""


class CheckFailed(Exception):
    """A check found something other than what the review expects."""


# --- Parsing, with no device needed (covered by the unit tests) ---


def focused_window(dumpsys_window: str) -> str | None:
    """The focused window of `dumpsys window`: a package, or a system window
    name such as NotificationShade; None when nothing has focus."""
    match = re.search(
        r"mCurrentFocus=(?:Window\{\S+ \S+ ([^}\s]+)\}|null)", dumpsys_window
    )
    if match is None or match.group(1) is None:
        return None
    return match.group(1).split("/", 1)[0]


def keyguard_showing(dumpsys_window: str) -> bool:
    """Whether `dumpsys window` says the lock screen is up. The lock screen
    is focused as NotificationShade too, so the window alone cannot tell it
    from the shade a check opened."""
    return re.search(r"isKeyguardShowing=true\b", dumpsys_window) is not None


def may_touch(window: str | None, allow_shade: bool, locked: bool = False) -> bool:
    """The guard's decision: only SignalHub, or the shade when a check opened
    it, may receive taps and swipes, and never while the phone is locked."""
    if locked:
        return False
    if window == APP_PACKAGE:
        return True
    return allow_shade and window in SHADE_WINDOWS


def channel_importance(
    dumpsys_notification: str, package: str, channel: str
) -> int | None:
    """The importance of one app's notification channel, from
    `dumpsys notification`; None if the app has no such channel."""
    in_app = False
    for line in dumpsys_notification.splitlines():
        settings = re.search(r"AppSettings: (\S+) \(", line)
        if settings:
            in_app = settings.group(1) == package
            continue
        if in_app and f"mId='{channel}'" in line:
            importance = re.search(r"mImportance=(-?\d+)", line)
            return int(importance.group(1)) if importance else None
    return None


@dataclass(frozen=True)
class PostedNotification:
    package: str
    channel: str | None
    title: str | None


def posted_notifications(dumpsys_notification: str) -> list[PostedNotification]:
    """The notifications on show, from `dumpsys notification --noredact`."""
    records = re.split(r"\n\s*NotificationRecord\(", "\n" + dumpsys_notification)[1:]
    posted = []
    for record in records:
        package = re.search(r"pkg=(\S+)", record)
        if package is None:
            continue
        channel = re.search(r"Notification\(channel=(\S+)", record)
        title = re.search(r"android\.title=\w+ \((.*)\)\s*$", record, re.MULTILINE)
        posted.append(
            PostedNotification(
                package.group(1),
                channel.group(1) if channel else None,
                title.group(1) if title else None,
            )
        )
    return posted


@dataclass(frozen=True)
class Node:
    text: str
    description: str
    bounds: tuple[int, int, int, int]
    focused: bool
    package: str

    @property
    def label(self) -> str:
        return "\n".join(part for part in (self.text, self.description) if part)

    @property
    def center(self) -> tuple[int, int]:
        left, top, right, bottom = self.bounds
        return (left + right) // 2, (top + bottom) // 2


def ui_nodes(hierarchy: str) -> list[Node]:
    """Every node of a `uiautomator dump`, which may be followed by its own
    status line."""
    end = hierarchy.find("</hierarchy>")
    if end < 0:
        raise ValueError("not a uiautomator hierarchy")
    root = ElementTree.fromstring(
        hierarchy[hierarchy.find("<") : end + len("</hierarchy>")]
    )
    nodes = []
    for element in root.iter("node"):
        numbers = [int(n) for n in re.findall(r"-?\d+", element.get("bounds", ""))]
        if len(numbers) != 4:
            continue
        nodes.append(
            Node(
                text=element.get("text", ""),
                description=element.get("content-desc", ""),
                bounds=(numbers[0], numbers[1], numbers[2], numbers[3]),
                focused=element.get("focused") == "true",
                package=element.get("package", ""),
            )
        )
    return nodes


def find_node(nodes: list[Node], label: str, exact: bool = False) -> Node | None:
    """The first node whose text or description is, or contains, the label."""
    for node in nodes:
        lines = node.label.split("\n")
        if (label in lines) if exact else (label in node.label):
            return node
    return None


def unread_badge(nodes: list[Node]) -> int:
    """The inbox's unread count: the number on the app bar's title, or beside
    it, or 0 when no badge is shown."""
    title = find_node(nodes, "SignalHub", exact=True)
    if title is None:
        raise ValueError("no SignalHub title on the screen")
    numbers = [line for line in title.label.split("\n") if line.isdigit()]
    if numbers:
        return int(numbers[0])
    top, bottom = title.bounds[1], title.bounds[3]
    for node in nodes:
        if node.text.isdigit() and top <= node.center[1] <= bottom:
            return int(node.text)
    return 0


def log_problems(lines: list[str]) -> list[str]:
    """The backend log lines at WARN level or above."""
    return [line for line in lines if LOG_PROBLEM.search(line)]


# --- Configuration ---


@dataclass(frozen=True)
class Config:
    serial: str
    server: str
    producer_key: str
    client_key: str
    client_id: str
    admin_token: str
    output: Path
    compose_dir: Path
    compose_service: str


def _read_secret(path: str | None, what: str) -> str:
    if not path:
        raise SystemExit(f"{what}: give a file (see --help)")
    try:
        value = Path(path).read_text(encoding="utf-8").strip()
    except OSError as error:
        raise SystemExit(f"{what}: {error}") from error
    if not value:
        raise SystemExit(f"{what}: {path} is empty")
    return value


def _required(value: str | None, what: str) -> str:
    if not value:
        raise SystemExit(f"{what} is required (see --help)")
    return value


def parse_args(
    argv: list[str], environ: dict[str, str]
) -> tuple[argparse.Namespace, Config | None]:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--list", action="store_true", help="list the checks and exit")
    parser.add_argument(
        "--check",
        action="append",
        choices=[check.name for check in CHECKS],
        help="run only this check (repeatable); default: all, in order",
    )
    env = environ.get
    parser.add_argument(
        "--serial", default=env("ANDROID_SERIAL"), help="adb serial (ANDROID_SERIAL)"
    )
    parser.add_argument(
        "--server",
        default=env("SIGNALHUB_URL"),
        help="server address as the computer reaches it (SIGNALHUB_URL)",
    )
    parser.add_argument(
        "--producer-key-file",
        default=env("SIGNALHUB_PRODUCER_KEY_FILE"),
        help="file with the producer API key (SIGNALHUB_PRODUCER_KEY_FILE)",
    )
    parser.add_argument(
        "--client-key-file",
        default=env("SIGNALHUB_CLIENT_KEY_FILE"),
        help="file with the app's client key (SIGNALHUB_CLIENT_KEY_FILE)",
    )
    parser.add_argument(
        "--client-id",
        default=env("SIGNALHUB_CLIENT_ID"),
        help="the app's client ID (SIGNALHUB_CLIENT_ID)",
    )
    parser.add_argument(
        "--admin-token-file",
        default=env("SIGNALHUB_ADMIN_TOKEN_FILE"),
        help="file with the admin token (SIGNALHUB_ADMIN_TOKEN_FILE)",
    )
    parser.add_argument(
        "--output",
        default=env("SIGNALHUB_REVIEW_OUTPUT"),
        help="directory for screenshots, dumps and results (SIGNALHUB_REVIEW_OUTPUT)",
    )
    parser.add_argument(
        "--compose-dir",
        default=env("SIGNALHUB_COMPOSE_DIR", "."),
        help="directory of the stack's compose.yaml (SIGNALHUB_COMPOSE_DIR, default: .)",
    )
    parser.add_argument(
        "--compose-service", default="backend", help="the backend's Compose service"
    )
    args = parser.parse_args(argv)
    if args.list:
        return args, None
    config = Config(
        serial=_required(args.serial, "--serial or ANDROID_SERIAL"),
        server=_required(args.server, "--server or SIGNALHUB_URL").rstrip("/"),
        producer_key=_read_secret(args.producer_key_file, "producer key"),
        client_key=_read_secret(args.client_key_file, "client key"),
        client_id=_required(args.client_id, "--client-id or SIGNALHUB_CLIENT_ID"),
        admin_token=_read_secret(args.admin_token_file, "admin token"),
        output=Path(_required(args.output, "--output or SIGNALHUB_REVIEW_OUTPUT")),
        compose_dir=Path(args.compose_dir),
        compose_service=args.compose_service,
    )
    return args, config


# --- The device ---


class Device:
    """adb with the safety guard in front of every tap and swipe."""

    def __init__(self, serial: str, output: Path):
        self.serial = serial
        self.output = output
        self.shade_allowed = False

    def adb(self, *args: str, check: bool = True) -> str:
        result = subprocess.run(
            ["adb", "-s", self.serial, *args],
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )
        if check and result.returncode != 0:
            raise CheckFailed(f"adb {' '.join(args)}: {result.stderr.strip()}")
        return result.stdout

    def shell(self, command: str, check: bool = True) -> str:
        return self.adb("shell", command, check=check)

    def window(self) -> str | None:
        return focused_window(self.shell("dumpsys window"))

    def guard(self) -> None:
        dump = self.shell("dumpsys window")
        window, locked = focused_window(dump), keyguard_showing(dump)
        if not may_touch(window, self.shade_allowed, locked):
            what = "the lock screen" if locked else (window or "nothing")
            raise GuardError(f"not touching the screen: {what} is in front")

    def tap(self, node: Node) -> None:
        self.guard()
        x, y = node.center
        self.shell(f"input tap {x} {y}")

    def pull_to_refresh(self) -> None:
        self.guard()
        width, height = self.screen_size()
        x = width // 2
        self.shell(f"input swipe {x} {height // 4} {x} {height * 3 // 4} 400")

    def screen_size(self) -> tuple[int, int]:
        size = re.search(r"(\d+)x(\d+)", self.shell("wm size"))
        if size is None:
            raise CheckFailed("unknown screen size")
        return int(size.group(1)), int(size.group(2))

    def nodes(self) -> list[Node]:
        return ui_nodes(self.adb("exec-out", "uiautomator", "dump", "/dev/tty"))

    def wait_for(self, label: str, timeout: float = 20.0, exact: bool = False) -> Node:
        deadline = time.monotonic() + timeout
        while True:
            node = find_node(self.nodes(), label, exact)
            if node is not None:
                return node
            if time.monotonic() > deadline:
                raise CheckFailed(f"{label!r} not on the screen after {timeout:.0f} s")
            time.sleep(1)

    def tap_label(self, label: str, timeout: float = 20.0, exact: bool = False) -> None:
        self.tap(self.wait_for(label, timeout, exact))

    def notifications(self) -> list[PostedNotification]:
        return posted_notifications(self.shell("dumpsys notification --noredact"))

    def app_notifications(self, title: str) -> list[PostedNotification]:
        return [
            n
            for n in self.notifications()
            if n.package == APP_PACKAGE and n.title == title
        ]

    def wait_for_notification(
        self, title: str, timeout: float = PUSH_WAIT
    ) -> PostedNotification:
        deadline = time.monotonic() + timeout
        while True:
            posted = self.app_notifications(title)
            if posted:
                return posted[0]
            if time.monotonic() > deadline:
                raise CheckFailed(f"no notification {title!r} after {timeout:.0f} s")
            time.sleep(2)

    def start_app(self) -> None:
        self.shell(f"am start -W -n {APP_ACTIVITY}")
        self.wait_for_window(APP_PACKAGE)

    def wait_for_window(self, window: str, timeout: float = 20.0) -> None:
        deadline = time.monotonic() + timeout
        while self.window() != window:
            if time.monotonic() > deadline:
                raise CheckFailed(f"{window} not in front after {timeout:.0f} s")
            time.sleep(1)

    def home(self) -> None:
        self.shell("input keyevent KEYCODE_HOME")
        time.sleep(1)

    def back(self) -> None:
        self.shell("input keyevent KEYCODE_BACK")
        time.sleep(1)

    def open_shade(self) -> None:
        self.shell("cmd statusbar expand-notifications")
        self.shade_allowed = True
        time.sleep(1)

    def close_shade(self) -> None:
        self.shade_allowed = False
        self.shell("cmd statusbar collapse", check=False)

    def app_running(self) -> bool:
        return bool(self.shell(f"pidof {APP_PACKAGE}", check=False).strip())

    def screenshot(self, name: str) -> Path:
        path = self.output / f"{name}.png"
        with path.open("wb") as file:
            subprocess.run(
                ["adb", "-s", self.serial, "exec-out", "screencap", "-p"],
                stdout=file,
                check=True,
                timeout=60,
            )
        return path

    def set_airplane_mode(self, enabled: bool) -> None:
        self.shell(
            f"cmd connectivity airplane-mode {'enable' if enabled else 'disable'}"
        )


def pixels_differ(first: Path, second: Path, crop: str) -> int:
    """How many pixels differ between two screenshots in a region, with
    ImageMagick's compare (geometry such as 1080x400+0+0)."""
    result = subprocess.run(
        [
            "compare",
            "-metric",
            "AE",
            f"{first}[{crop}]",
            f"{second}[{crop}]",
            "null:",
        ],
        capture_output=True,
        text=True,
        timeout=60,
        check=False,
    )
    # compare exits 1 when the images differ; the count is on stderr.
    count = re.match(r"\s*(\d+)", result.stderr)
    if result.returncode > 1 or count is None:
        raise CheckFailed(f"compare failed: {result.stderr.strip()}")
    return int(count.group(1))


# --- The server ---


class Server:
    def __init__(self, config: Config):
        self.config = config

    def request(
        self,
        method: str,
        path: str,
        credential: str,
        body: object | None = None,
        headers: dict[str, str] | None = None,
    ) -> object:
        data = None if body is None else json.dumps(body).encode()
        request = urllib.request.Request(
            self.config.server + path, data=data, method=method
        )
        request.add_header("Authorization", f"Bearer {credential}")
        if data is not None:
            request.add_header("Content-Type", "application/json")
        for name, value in (headers or {}).items():
            request.add_header(name, value)
        try:
            with urllib.request.urlopen(request, timeout=15) as response:
                text = response.read().decode()
        except urllib.error.HTTPError as error:
            raise CheckFailed(
                f"{method} {path}: {error.code} {error.read().decode()[:300]}"
            ) from error
        except urllib.error.URLError as error:
            raise CheckFailed(f"{method} {path}: {error.reason}") from error
        except (OSError, http.client.HTTPException) as error:
            # A backend that is starting behind Docker's port proxy accepts the
            # connection and then resets or closes it.
            raise CheckFailed(f"{method} {path}: {error!r}") from error
        return json.loads(text) if text else None

    def publish(
        self, title: str, severity: str = "HIGH", idempotency_key: str | None = None
    ) -> dict:
        body = {
            "category": "INFO",
            "severity": severity,
            "title": title,
            "message": "Published by the device review.",
            "context": "device-review",
        }
        headers = {"Idempotency-Key": idempotency_key} if idempotency_key else None
        return self.request(
            "POST", "/api/v1/events", self.config.producer_key, body, headers
        )

    def event(self, event_id: str) -> dict:
        return self.request("GET", f"/api/v1/events/{event_id}", self.config.client_key)

    def set_read(self, event_id: str, read: bool) -> dict:
        method = "PUT" if read else "DELETE"
        return self.request(
            method, f"/api/v1/events/{event_id}/read", self.config.client_key
        )

    def unread(self) -> int:
        return self.request(
            "GET", "/api/v1/events/unread-count", self.config.client_key
        )["unread"]

    def client(self) -> dict:
        answer = self.request(
            "GET",
            f"/api/v1/admin/clients/{self.config.client_id}",
            self.config.admin_token,
        )
        return answer.get("client", answer)

    def own_registration(self) -> dict:
        return self.request("GET", "/api/v1/client", self.config.client_key)

    def set_push_preferences(self, preferences: dict) -> dict:
        return self.request(
            "PUT",
            "/api/v1/client/push-preferences",
            self.config.client_key,
            preferences,
        )

    def reachable(self) -> bool:
        try:
            self.unread()
        except CheckFailed:
            return False
        return True

    def wait_until_reachable(self, timeout: float = 120.0) -> None:
        deadline = time.monotonic() + timeout
        while not self.reachable():
            if time.monotonic() > deadline:
                raise CheckFailed(f"the server is not back after {timeout:.0f} s")
            time.sleep(2)


# --- The stack ---


def compose(config: Config, *args: str) -> str:
    result = subprocess.run(
        ["docker", "compose", *args],
        cwd=config.compose_dir,
        capture_output=True,
        text=True,
        timeout=300,
        check=False,
    )
    if result.returncode != 0:
        raise CheckFailed(f"docker compose {' '.join(args)}: {result.stderr.strip()}")
    return result.stdout


# --- The checks ---


@dataclass
class Review:
    config: Config
    device: Device
    server: Server
    started: datetime = field(default_factory=lambda: datetime.now(timezone.utc))

    def title(self, what: str) -> str:
        return f"Device review: {what} {uuid.uuid4().hex[:6]}"

    def inbox(self) -> None:
        """SignalHub in front, on its inbox."""
        self.device.start_app()
        for _ in range(3):
            if find_node(self.device.nodes(), "SignalHub", exact=True):
                return
            self.device.back()
            if self.device.window() != APP_PACKAGE:
                self.device.start_app()
        raise CheckFailed("the inbox is not on the screen")

    def open_menu_item(self, item: str) -> None:
        self.inbox()
        self.device.tap_label(MENU)
        self.device.tap_label(item, exact=True)


def check_connected_start(review: Review) -> str:
    device = review.device
    device.shell(f"am force-stop {APP_PACKAGE}")
    device.start_app()
    device.wait_for("SignalHub", exact=True)
    nodes = device.nodes()
    if find_node(nodes, "Connect", exact=True):
        raise CheckFailed("the app shows its setup screen, not the inbox")
    shown, unread = unread_badge(nodes), review.server.unread()
    if shown != unread:
        raise CheckFailed(f"the inbox shows {shown} unread, the server {unread}")
    return f"{unread} unread on both"


def check_device_push_on(review: Review) -> str:
    review.open_menu_item(DEVICE_ITEM)
    review.device.wait_for(PUSH_ON)
    review.device.back()
    return PUSH_ON


def check_server_push_target(review: Review) -> str:
    target = review.server.client().get("pushTarget")
    if not target or target.get("provider") != "fcm":
        raise CheckFailed(f"the server's push target is {target}")
    return f"fcm, updated {target.get('updatedAt')}"


def check_events_channel(review: Review) -> str:
    dump = review.device.shell("dumpsys notification")
    importance = channel_importance(dump, APP_PACKAGE, EVENTS_CHANNEL)
    if importance is None or importance < IMPORTANCE_HIGH:
        raise CheckFailed(f"the {EVENTS_CHANNEL} channel's importance is {importance}")
    return f"importance {importance}"


def check_foreground_push(review: Review) -> str:
    review.inbox()
    title = review.title("foreground")
    review.server.publish(title)
    review.device.wait_for(title, timeout=PUSH_WAIT)
    if review.device.app_notifications(title):
        raise CheckFailed("a push in the foreground posted a system notification")
    return "in the inbox, no system notification"


def open_from_shade(review: Review, title: str) -> None:
    device = review.device
    device.open_shade()
    try:
        device.tap_label(title)
    finally:
        device.shade_allowed = False
    device.wait_for_window(APP_PACKAGE)
    device.wait_for(EVENT_SCREEN_TITLE, exact=True)
    device.wait_for(title)


def check_background_push(review: Review) -> str:
    review.inbox()
    review.device.home()
    title = review.title("background")
    event = review.server.publish(title)
    posted = review.device.wait_for_notification(title)
    if posted.channel != EVENTS_CHANNEL:
        raise CheckFailed(f"the notification is in channel {posted.channel}")
    open_from_shade(review, title)
    if review.server.event(event["id"]).get("readAt") is None:
        raise CheckFailed(
            "opening the event from its notification did not mark it read"
        )
    return "in the events channel; tapping it opened the event and marked it read"


def check_refresh_on_return(review: Review) -> str:
    review.inbox()
    review.device.home()
    title = review.title("return")
    review.server.publish(title, severity="LOW")
    time.sleep(3)
    review.device.start_app()
    review.device.wait_for(title)
    return "the inbox shows the event published while away"


def check_killed_app_push(review: Review) -> str:
    device = review.device
    review.inbox()
    device.home()
    # As the system kills an app in the background; a force-stopped app gets
    # no pushes on Android until it is started again.
    device.shell(f"am kill {APP_PACKAGE}")
    time.sleep(2)
    if device.app_running():
        raise CheckFailed("the app is still running after am kill")
    title = review.title("killed")
    review.server.publish(title)
    device.wait_for_notification(title)
    open_from_shade(review, title)
    return "the push arrived and a cold start opened its event"


def check_force_stop_reregisters(review: Review) -> str:
    before = (review.server.client().get("pushTarget") or {}).get("updatedAt")
    review.device.shell(f"am force-stop {APP_PACKAGE}")
    review.inbox()
    deadline = time.monotonic() + 30
    while True:
        target = review.server.client().get("pushTarget") or {}
        if target.get("provider") == "fcm" and target.get("updatedAt") != before:
            return f"push target updated at {target['updatedAt']}"
        if time.monotonic() > deadline:
            raise CheckFailed(f"the push target was not set again (still {before})")
        time.sleep(2)


def check_read_state(review: Review) -> str:
    device, server = review.device, review.server
    review.inbox()
    title = review.title("read state")
    event = server.publish(title, severity="LOW")
    device.pull_to_refresh()
    device.tap_label(title)
    device.wait_for(MARK_UNREAD)
    if server.event(event["id"]).get("readAt") is None:
        raise CheckFailed("opening the event did not mark it read")
    device.tap_label(MARK_UNREAD)
    device.wait_for("SignalHub", exact=True)
    if server.event(event["id"]).get("readAt") is not None:
        raise CheckFailed("Mark as unread did not reach the server")
    if unread_badge(device.nodes()) != server.unread():
        raise CheckFailed(
            "the inbox's unread count differs from the server's after Mark as unread"
        )
    server.set_read(event["id"], True)
    device.pull_to_refresh()
    time.sleep(2)
    if unread_badge(device.nodes()) != server.unread():
        raise CheckFailed("the inbox did not follow a read mark made elsewhere")
    return (
        "opening marks read, Mark as unread and marks made elsewhere show in the inbox"
    )


def check_push_preferences(review: Review) -> str:
    device, server = review.device, review.server
    saved = server.own_registration()["pushPreferences"]
    try:
        review.open_menu_item(NOTIFICATIONS_ITEM)
        device.tap_label(PUSH_SWITCH, exact=True)
        time.sleep(2)
        if server.own_registration()["pushPreferences"]["enabled"]:
            raise CheckFailed("switching push off did not reach the server")
        device.home()
        paused = review.title("paused")
        server.publish(paused)
        # Preferences apply when the dispatcher sends an event, not when it is
        # published, so the paused event must be dispatched before they change.
        time.sleep(QUIET_WAIT)
        if device.app_notifications(paused):
            raise CheckFailed(f"{paused!r} was pushed while push was off")
        server.set_push_preferences({"enabled": True, "minimumSeverity": "HIGH"})
        low, high = review.title("low"), review.title("high")
        server.publish(low, severity="LOW")
        server.publish(high, severity="HIGH")
        device.wait_for_notification(high)
        time.sleep(QUIET_WAIT)
        if device.app_notifications(low):
            raise CheckFailed(f"{low!r} was pushed below the minimum severity")
    finally:
        server.set_push_preferences(saved)
    return "paused: no push; minimum HIGH: only the HIGH event pushed"


def check_idempotent_publish(review: Review) -> str:
    review.inbox()
    review.device.home()
    title, key = review.title("idempotent"), uuid.uuid4().hex
    first = review.server.publish(title, idempotency_key=key)
    second = review.server.publish(title, idempotency_key=key)
    if first["id"] != second["id"]:
        raise CheckFailed("the repeated publish stored a second event")
    review.device.wait_for_notification(title)
    time.sleep(QUIET_WAIT)
    count = len(review.device.app_notifications(title))
    if count != 1:
        raise CheckFailed(f"{count} notifications for one event")
    return "one event, one notification"


def check_backend_down(review: Review) -> str:
    device, server = review.device, review.server
    review.inbox()
    title = review.title("backend down")
    event = server.publish(title, severity="LOW")
    device.pull_to_refresh()
    device.wait_for(title)
    try:
        compose(review.config, "stop", review.config.compose_service)
        device.pull_to_refresh()
        time.sleep(3)
        if device.window() != APP_PACKAGE:
            raise CheckFailed("the app left the screen with the backend down")
        device.screenshot("backend-down-inbox")
        # Marking read on opening fails, so the event screen offers Mark as read.
        device.tap_label(title)
        device.wait_for(MARK_READ)
    finally:
        compose(review.config, "start", review.config.compose_service)
    server.wait_until_reachable()
    device.tap_label(MARK_READ)
    device.wait_for(MARK_UNREAD)
    if server.event(event["id"]).get("readAt") is None:
        raise CheckFailed("Mark as read after the recovery did not reach the server")
    device.back()
    device.pull_to_refresh()
    device.wait_for(title)
    return "the app kept going, and Mark as read worked once the backend was back"


def check_offline_push(review: Review) -> str:
    device = review.device
    review.inbox()
    device.home()
    title = review.title("offline")
    try:
        device.set_airplane_mode(True)
        time.sleep(5)
        review.server.publish(title)
        time.sleep(QUIET_WAIT)
        if device.app_notifications(title):
            raise CheckFailed(
                "a push arrived in airplane mode; is the phone still online?"
            )
    finally:
        device.set_airplane_mode(False)
    device.wait_for_notification(title, timeout=180)
    return "arrived after the phone reconnected"


def check_popup_over_other_app(review: Review) -> str:
    device = review.device
    device.shell("am start -W -a android.settings.SETTINGS")
    time.sleep(2)
    before = device.screenshot("popup-before")
    title = review.title("pop-up")
    review.server.publish(title)
    device.wait_for_notification(title)
    after = device.screenshot("popup-after")
    width, height = device.screen_size()
    changed = pixels_differ(before, after, f"{width}x{height // 5}+0+0")
    device.home()
    if changed < width * 20:
        raise CheckFailed(f"only {changed} pixels changed at the top: no pop-up shown")
    return f"a pop-up over Settings ({changed} pixels changed at the top)"


def check_backend_restart(review: Review) -> str:
    compose(review.config, "restart", review.config.compose_service)
    review.server.wait_until_reachable()
    review.inbox()
    review.device.home()
    title = review.title("after restart")
    review.server.publish(title)
    review.device.wait_for_notification(title)
    review.device.start_app()
    review.device.wait_for(title)
    return "pushes and the inbox work after a restart"


def check_no_focus_border(review: Review) -> str:
    review.inbox()
    review.device.screenshot("inbox")
    focused = [
        node.label
        for node in review.device.nodes()
        if node.focused and node.package == APP_PACKAGE
    ]
    if focused:
        raise CheckFailed(f"keyboard focus on {focused} (see inbox.png)")
    return "nothing focused (see inbox.png)"


def check_backend_log(review: Review) -> str:
    since = review.started.strftime("%Y-%m-%dT%H:%M:%SZ")
    lines = compose(
        review.config,
        "logs",
        "--no-color",
        "--since",
        since,
        review.config.compose_service,
    ).splitlines()
    (review.config.output / "backend.log").write_text(
        "\n".join(lines) + "\n", encoding="utf-8"
    )
    problems = log_problems(lines)
    if problems:
        raise CheckFailed(f"{len(problems)} WARN/ERROR lines, first: {problems[0]}")
    return f"{len(lines)} lines, none at WARN or above"


@dataclass(frozen=True)
class Check:
    name: str
    run: Callable[[Review], str]
    summary: str


CHECKS = [
    Check(
        "connected-start",
        check_connected_start,
        "starts on the inbox with the server's unread count",
    ),
    Check("device-push-on", check_device_push_on, "This device shows push on"),
    Check(
        "server-push-target",
        check_server_push_target,
        "the server has an fcm push target",
    ),
    Check(
        "events-channel",
        check_events_channel,
        "the Events channel is at high importance",
    ),
    Check(
        "foreground-push",
        check_foreground_push,
        "a foreground push goes to the inbox, no notification",
    ),
    Check(
        "background-push",
        check_background_push,
        "a background push in Events; tapping opens and marks read",
    ),
    Check(
        "refresh-on-return",
        check_refresh_on_return,
        "returning to the app refreshes the inbox",
    ),
    Check(
        "killed-app-push",
        check_killed_app_push,
        "a push to a killed app arrives; a cold start opens it",
    ),
    Check(
        "force-stop-reregisters",
        check_force_stop_reregisters,
        "force-stop and relaunch set the push target",
    ),
    Check("read-state", check_read_state, "read state syncs both ways"),
    Check(
        "push-preferences",
        check_push_preferences,
        "pause and minimum severity filter pushes (restored)",
    ),
    Check(
        "idempotent-publish",
        check_idempotent_publish,
        "a repeated publish gives one push",
    ),
    Check(
        "backend-down",
        check_backend_down,
        "backend down, then back; Mark as read (stops the backend)",
    ),
    Check(
        "offline-push",
        check_offline_push,
        "a push sent offline arrives after reconnecting (airplane mode)",
    ),
    Check(
        "popup-over-other-app",
        check_popup_over_other_app,
        "a pop-up over another app (opens Settings)",
    ),
    Check(
        "backend-restart",
        check_backend_restart,
        "works after a backend restart (restarts the backend)",
    ),
    Check(
        "no-focus-border",
        check_no_focus_border,
        "no keyboard focus border in the inbox",
    ),
    Check(
        "backend-log",
        check_backend_log,
        "no WARN or ERROR in the backend log since the start",
    ),
]


def run(review: Review, checks: list[Check]) -> bool:
    results = []
    aborted = None
    for check in checks:
        started = time.monotonic()
        try:
            detail, passed = check.run(review), True
        except CheckFailed as failure:
            detail, passed = str(failure), False
        except GuardError as guard:
            aborted = str(guard)
            results.append({"check": check.name, "passed": False, "detail": aborted})
            print(f"ABORT {check.name}: {aborted}")
            break
        finally:
            review.device.close_shade()
        results.append({"check": check.name, "passed": passed, "detail": detail})
        print(
            f"{'PASS' if passed else 'FAIL'} {check.name} ({time.monotonic() - started:.0f} s): {detail}"
        )
        if not passed:
            review.device.screenshot(f"failed-{check.name}")
    report = {
        "started": review.started.isoformat(),
        "aborted": aborted,
        "results": results,
    }
    (review.config.output / "results.json").write_text(
        json.dumps(report, indent=2) + "\n", encoding="utf-8"
    )
    return aborted is None and all(result["passed"] for result in results)


def main(argv: list[str] | None = None) -> int:
    args, config = parse_args(sys.argv[1:] if argv is None else argv, dict(os.environ))
    if config is None:
        for check in CHECKS:
            print(f"{check.name:24} {check.summary}")
        return 0
    config.output.mkdir(parents=True, exist_ok=True)
    selected = [check for check in CHECKS if not args.check or check.name in args.check]
    review = Review(config, Device(config.serial, config.output), Server(config))
    return 0 if run(review, selected) else 1


if __name__ == "__main__":
    sys.exit(main())
