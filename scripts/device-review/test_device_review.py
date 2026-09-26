import tempfile
import unittest
from pathlib import Path

import device_review
from device_review import (
    APP_PACKAGE,
    Device,
    GuardError,
    Node,
    channel_importance,
    find_node,
    focused_window,
    keyguard_showing,
    log_problems,
    may_touch,
    parse_args,
    posted_notifications,
    ui_nodes,
    unread_badge,
)

SAMPLES = Path(__file__).parent / "samples"


def sample(name: str) -> str:
    return (SAMPLES / name).read_text(encoding="utf-8")


class FocusedWindowTest(unittest.TestCase):
    def test_windows(self):
        cases = {
            "window-app.txt": APP_PACKAGE,
            "window-shade.txt": "NotificationShade",
            "window-other-app.txt": "com.android.settings",
            "window-permission.txt": "com.google.android.permissioncontroller",
            "window-none.txt": None,
        }
        for name, expected in cases.items():
            with self.subTest(name):
                self.assertEqual(focused_window(sample(name)), expected)

    def test_no_focus_line(self):
        self.assertIsNone(focused_window("WINDOW MANAGER WINDOWS\n"))


class KeyguardTest(unittest.TestCase):
    def test_locked(self):
        self.assertTrue(keyguard_showing(sample("window-locked.txt")))

    def test_unlocked(self):
        for name in ("window-app.txt", "window-shade.txt", "window-other-app.txt"):
            with self.subTest(name):
                self.assertFalse(keyguard_showing(sample(name)))


class GuardDecisionTest(unittest.TestCase):
    def test_signalhub_in_front(self):
        self.assertTrue(may_touch(APP_PACKAGE, allow_shade=False))
        self.assertTrue(may_touch(APP_PACKAGE, allow_shade=True))

    def test_shade_only_when_a_check_opened_it(self):
        for shade in ("NotificationShade", "StatusBar"):
            with self.subTest(shade):
                self.assertTrue(may_touch(shade, allow_shade=True))
                self.assertFalse(may_touch(shade, allow_shade=False))

    def test_never_while_locked(self):
        for window in (APP_PACKAGE, "NotificationShade"):
            with self.subTest(window):
                self.assertFalse(may_touch(window, allow_shade=True, locked=True))

    def test_anything_else_is_refused(self):
        for window in (
            "com.android.settings",
            "com.google.android.permissioncontroller",
            APP_PACKAGE + ".other",
            None,
        ):
            with self.subTest(window):
                self.assertFalse(may_touch(window, allow_shade=True))


class FakeDevice(Device):
    """Answers `dumpsys window` from a sample and records other commands."""

    def __init__(self, window_sample: str):
        super().__init__("test-serial", Path("."))
        self.window_sample = window_sample
        self.commands: list[str] = []

    def shell(self, command: str, check: bool = True) -> str:
        if command == "dumpsys window":
            return sample(self.window_sample)
        if command == "wm size":
            return "Physical size: 1080x2400\n"
        self.commands.append(command)
        return ""


class GuardTest(unittest.TestCase):
    node = Node("", "Show menu", (932, 147, 1058, 273), False, APP_PACKAGE)

    def test_taps_signalhub(self):
        device = FakeDevice("window-app.txt")
        device.tap(self.node)
        self.assertEqual(device.commands, ["input tap 995 210"])

    def test_refuses_another_app_without_touching(self):
        for window in (
            "window-other-app.txt",
            "window-permission.txt",
            "window-none.txt",
        ):
            with self.subTest(window):
                device = FakeDevice(window)
                with self.assertRaises(GuardError):
                    device.tap(self.node)
                with self.assertRaises(GuardError):
                    device.pull_to_refresh()
                self.assertEqual(device.commands, [])

    def test_shade_only_after_opening_it(self):
        device = FakeDevice("window-shade.txt")
        with self.assertRaises(GuardError):
            device.tap(self.node)
        device.open_shade()
        device.tap(self.node)
        self.assertEqual(device.commands[-1], "input tap 995 210")
        device.close_shade()
        with self.assertRaises(GuardError):
            device.tap(self.node)

    def test_refuses_the_lock_screen_even_with_the_shade_opened(self):
        # Locked, the focused window is NotificationShade, as for the shade.
        device = FakeDevice("window-locked.txt")
        device.open_shade()
        with self.assertRaises(GuardError):
            device.tap(self.node)
        with self.assertRaises(GuardError):
            device.pull_to_refresh()
        self.assertEqual(device.commands, ["cmd statusbar expand-notifications"])

    def test_pull_to_refresh_swipes_down(self):
        device = FakeDevice("window-app.txt")
        device.pull_to_refresh()
        self.assertEqual(device.commands, ["input swipe 540 600 540 1800 400"])


class NotificationTest(unittest.TestCase):
    def test_channel_importance_is_the_apps_own(self):
        dump = sample("notification.txt")
        self.assertEqual(channel_importance(dump, APP_PACKAGE, "events"), 4)
        self.assertEqual(
            channel_importance(dump, APP_PACKAGE, "fcm_fallback_notification_channel"),
            3,
        )
        self.assertEqual(channel_importance(dump, "com.android.systemui", "events"), 2)

    def test_missing_channel(self):
        dump = sample("notification.txt")
        self.assertIsNone(channel_importance(dump, APP_PACKAGE, "other"))
        self.assertIsNone(channel_importance(dump, "com.example.absent", "events"))

    def test_posted_notifications(self):
        posted = posted_notifications(sample("notification.txt"))
        self.assertEqual(
            [(n.package, n.channel, n.title) for n in posted],
            [
                (APP_PACKAGE, "events", "Device review: background 3f9a1c"),
                ("com.android.systemui", "BAT", "Battery at 81%"),
                (
                    APP_PACKAGE,
                    "fcm_fallback_notification_channel",
                    "An older push (in parentheses)",
                ),
            ],
        )

    def test_nothing_posted(self):
        self.assertEqual(
            posted_notifications("Current Notification Manager state:\n"), []
        )


class UiTest(unittest.TestCase):
    def test_nodes_after_the_dump_status_line(self):
        nodes = ui_nodes(sample("inbox.xml"))
        self.assertEqual(len(nodes), 5)
        menu = find_node(nodes, "Show menu", exact=True)
        self.assertEqual(menu.bounds, (932, 147, 1058, 273))
        self.assertEqual(menu.center, (995, 210))

    def test_find_node(self):
        nodes = ui_nodes(sample("inbox.xml"))
        event = find_node(nodes, "foreground 1b2c3d")
        self.assertEqual(event.bounds, (0, 294, 1080, 504))
        self.assertIsNone(find_node(nodes, "foreground 1b2c3d", exact=True))
        self.assertIsNotNone(find_node(nodes, "SignalHub", exact=True))
        # "Mark as read" is not part of "Mark all as read".
        self.assertIsNone(find_node(nodes, "Mark as read"))

    def test_not_a_hierarchy(self):
        with self.assertRaises(ValueError):
            ui_nodes("ERROR: could not get idle state.")

    def test_unread_badge(self):
        self.assertEqual(unread_badge(ui_nodes(sample("inbox.xml"))), 3)
        self.assertEqual(unread_badge(ui_nodes(sample("inbox-separate-badge.xml"))), 12)
        # Numbers in events further down are not the badge.
        self.assertEqual(unread_badge(ui_nodes(sample("inbox-all-read.xml"))), 0)

    def test_unread_badge_needs_the_inbox(self):
        with self.assertRaises(ValueError):
            unread_badge([])

    def test_focused(self):
        focused = [
            n.label for n in ui_nodes(sample("inbox-separate-badge.xml")) if n.focused
        ]
        self.assertEqual(focused, ["Build 42\n7 checks passed"])
        self.assertFalse(any(n.focused for n in ui_nodes(sample("inbox.xml"))))


class LogTest(unittest.TestCase):
    def test_problems_are_levels_not_words(self):
        problems = log_problems(sample("backend.log").splitlines())
        self.assertEqual(len(problems), 3)
        self.assertIn("WARN  [io.agroal.pool]", problems[0])
        self.assertIn("ERROR [io.qua.ver", problems[1])
        self.assertIn('"level":"WARN"', problems[2])


class ConfigTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.dir = Path(directory.name)
        for name, value in (
            ("producer", "shpk1_p\n"),
            ("client", "shck1_c\n"),
            ("admin", "a" * 40),
        ):
            (self.dir / name).write_text(value, encoding="utf-8")
        self.environ = {
            "ANDROID_SERIAL": "serial-from-env",
            "SIGNALHUB_URL": "http://localhost:8080/",
            "SIGNALHUB_PRODUCER_KEY_FILE": str(self.dir / "producer"),
            "SIGNALHUB_CLIENT_KEY_FILE": str(self.dir / "client"),
            "SIGNALHUB_CLIENT_ID": "client-id",
            "SIGNALHUB_ADMIN_TOKEN_FILE": str(self.dir / "admin"),
            "SIGNALHUB_REVIEW_OUTPUT": str(self.dir / "out"),
        }

    def test_from_the_environment_with_keys_from_files(self):
        _, config = parse_args([], self.environ)
        self.assertEqual(config.serial, "serial-from-env")
        self.assertEqual(config.server, "http://localhost:8080")
        self.assertEqual(config.producer_key, "shpk1_p")
        self.assertEqual(config.client_key, "shck1_c")
        self.assertEqual(config.admin_token, "a" * 40)
        self.assertEqual(config.output, self.dir / "out")

    def test_arguments_win(self):
        _, config = parse_args(
            ["--serial", "other", "--client-id", "id-2"], self.environ
        )
        self.assertEqual((config.serial, config.client_id), ("other", "id-2"))

    def test_no_defaults_for_machine_values(self):
        for name in (
            "ANDROID_SERIAL",
            "SIGNALHUB_URL",
            "SIGNALHUB_PRODUCER_KEY_FILE",
            "SIGNALHUB_CLIENT_KEY_FILE",
            "SIGNALHUB_CLIENT_ID",
            "SIGNALHUB_ADMIN_TOKEN_FILE",
            "SIGNALHUB_REVIEW_OUTPUT",
        ):
            with self.subTest(name):
                environ = {k: v for k, v in self.environ.items() if k != name}
                with self.assertRaises(SystemExit):
                    parse_args([], environ)

    def test_empty_key_file(self):
        (self.dir / "client").write_text("\n", encoding="utf-8")
        with self.assertRaises(SystemExit):
            parse_args([], self.environ)

    def test_keys_are_not_options(self):
        with self.assertRaises(SystemExit):
            parse_args(["--client-key", "shck1_c"], self.environ)

    def test_list_needs_nothing(self):
        args, config = parse_args(["--list"], {})
        self.assertTrue(args.list)
        self.assertIsNone(config)

    def test_every_check_is_selectable(self):
        names = [check.name for check in device_review.CHECKS]
        self.assertEqual(len(names), len(set(names)))
        args, _ = parse_args(["--check", names[0], "--check", names[-1]], self.environ)
        self.assertEqual(args.check, [names[0], names[-1]])


if __name__ == "__main__":
    unittest.main()
