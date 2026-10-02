import tempfile
import unittest
from pathlib import Path
from unittest import mock

import device_review
from device_review import (
    APP_PACKAGE,
    DEVICE_GROUP,
    PUSH_ON,
    CheckFailed,
    Device,
    GuardError,
    Node,
    Review,
    Server,
    alert_messages,
    channel_fields,
    channel_importance,
    check_alert_critical,
    check_alert_critical_quiet,
    check_alert_played,
    check_alert_quiet,
    check_foreground_push,
    check_popup_over_other_app,
    check_push_preferences,
    find_node,
    focused_window,
    group_row,
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
    node = Node("", "Settings", (932, 147, 1058, 273), False, APP_PACKAGE)

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

    def test_channel_fields(self):
        fields = channel_fields(
            sample("notification.txt"), APP_PACKAGE, "signalhub_events"
        )
        self.assertEqual(fields["mImportance"], "4")
        self.assertEqual(fields["mSound"], "null")
        self.assertEqual(fields["mVibrationEnabled"], "false")
        old = channel_fields(sample("notification.txt"), APP_PACKAGE, "events")
        self.assertEqual(old["mSound"], "content://settings/system/notification_sound")
        self.assertNotIn("mVibrationEnabled", old)

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


class AlertLogTest(unittest.TestCase):
    def test_push_alerts_not_previews(self):
        self.assertEqual(
            alert_messages(sample("logcat-alert.txt")),
            [
                (
                    "Alert played (sound on, vibration on): "
                    "sound=beacon volume=80% vibration=medium "
                    "pattern=standard length=short"
                ),
                (
                    "Alert not played (do not disturb): "
                    "sound=signal volume=80% vibration=medium "
                    "pattern=standard length=short"
                ),
                (
                    "Critical alert played (sound on, vibration on, as an alarm): "
                    "sound=urgent volume=100% vibration=strong "
                    "pattern=rapid length=long"
                ),
            ],
        )

    def test_nothing_logged(self):
        self.assertEqual(alert_messages("--------- beginning of main\n"), [])


# What the app logs for the general alert and a critical push's own, at
# their defaults.
GENERAL = "sound=signal volume=80% vibration=medium pattern=standard length=short"
OWN = "sound=urgent volume=100% vibration=strong pattern=rapid length=long"


class AlertCheckTest(unittest.TestCase):
    def review(self, logged: list[str]) -> tuple[Review, list[str]]:
        """A review whose app logs `logged`, one message per push."""
        self.severities: list[str] = []
        steps: list[str] = []
        device, server = mock.Mock(), mock.Mock()
        messages: list[str] = []
        pending = list(logged)

        def publish(title, severity="HIGH", **_):
            steps.append(f"publish {title}")
            self.severities.append(severity)
            messages.append(pending.pop(0))

        server.publish.side_effect = publish
        device.alert_messages.side_effect = lambda: list(messages)
        device.wait_for_alert.side_effect = lambda seen: messages[seen]
        device.tap_label.side_effect = lambda label, **_: steps.append(label)
        device.shell.side_effect = lambda command, **_: steps.append(command)
        device.scroll_to.side_effect = lambda label, **_: label
        device.tap.side_effect = lambda node: steps.append(
            f"tap {getattr(node, 'label', node)}"
        )
        # The Alert group's choice of pushes sounding on silent.
        device.scroll_to_upper_half.side_effect = lambda label, **_: row(label, 300)
        device.nodes.return_value = [
            row(label, 500) for label in ("Off", "Critical only", "All pushes")
        ]
        review = Review(fake_config(), device, server)
        review.title = lambda what: what
        review.inbox = lambda: None
        review.open_group = lambda group: steps.append(f"open {group[0]}")
        return review, steps

    def test_a_new_sound_is_the_next_and_the_first_is_restored(self):
        review, steps = self.review(
            [
                "Alert played (sound on, vibration on): sound=signal volume=80%",
                "Alert played (sound on, vibration on): sound=beacon volume=80%",
            ]
        )
        detail = check_alert_played(review)
        self.assertEqual(
            steps,
            [
                "publish alert",
                "open Alert",
                "tap Beacon",
                "publish changed alert",
                "open Alert",
                "tap Signal (default)",
            ],
        )
        self.assertIn("README.md", detail)

    def test_the_old_sound_again_fails_and_is_restored(self):
        review, steps = self.review(
            [
                "Alert played (sound on, vibration on): sound=beacon volume=80%",
                "Alert played (sound on, vibration on): sound=beacon volume=80%",
            ]
        )
        with self.assertRaisesRegex(CheckFailed, "not pulse"):
            check_alert_played(review)
        self.assertEqual(steps[-1], "tap Beacon")

    def test_an_alert_not_played_fails(self):
        review, _ = self.review(["Alert not played (silent mode): sound=signal"])
        with self.assertRaisesRegex(CheckFailed, "silent mode"):
            check_alert_played(review)

    def test_a_foreground_push_plays_its_alert_once(self):
        review, steps = self.review(
            [f"Alert played (sound on, vibration on): {GENERAL}"]
        )
        review.device.app_notifications.return_value = []
        with mock.patch("time.sleep"):
            detail = check_foreground_push(review)
        self.assertEqual(steps, ["publish foreground"])
        self.assertIn("played once (sound signal)", detail)

    def test_a_foreground_push_not_played_fails(self):
        review, _ = self.review([f"Alert not played (silent mode): {GENERAL}"])
        review.device.app_notifications.return_value = []
        with (
            mock.patch("time.sleep"),
            self.assertRaisesRegex(CheckFailed, "silent mode"),
        ):
            check_foreground_push(review)

    def test_a_foreground_push_played_twice_fails(self):
        played = f"Alert played (sound on, vibration on): {GENERAL}"
        review, _ = self.review([played])
        review.device.app_notifications.return_value = []

        def again(_):
            review.device.alert_messages.side_effect = lambda: [played, played]

        with (
            mock.patch("time.sleep", side_effect=again),
            self.assertRaisesRegex(CheckFailed, "twice"),
        ):
            check_foreground_push(review)

    def test_quiet_during_do_not_disturb_which_is_turned_off_again(self):
        review, steps = self.review(["Alert not played (do not disturb): sound=x"])
        with mock.patch("time.sleep"):
            check_alert_quiet(review)
        self.assertTrue(steps[0].startswith("cmd notification post"))
        self.assertEqual(steps[-1], "cmd notification set_dnd off")

    def test_an_alert_during_do_not_disturb_fails(self):
        review, steps = self.review(["Alert played (sound on, vibration on): x"])
        with (
            mock.patch("time.sleep"),
            self.assertRaisesRegex(CheckFailed, "during do-not-disturb"),
        ):
            check_alert_quiet(review)
        self.assertEqual(steps[-1], "cmd notification set_dnd off")

    def test_critical_pushes_play_their_own_alert_once_switched_on(self):
        review, steps = self.review(
            [
                f"Alert played (sound on, vibration on): {GENERAL}",
                f"Critical alert played (sound on, vibration on): {GENERAL}",
                f"Critical alert played (sound on, vibration on): {OWN}",
                f"Alert played (sound on, vibration on): {GENERAL}",
            ]
        )
        detail = check_alert_critical(review)
        self.assertEqual(self.severities, ["NORMAL", "CRITICAL", "CRITICAL", "NORMAL"])
        switch = "tap Different alert for critical events"
        self.assertEqual(steps.count(switch), 2)
        self.assertEqual(steps[2:4], ["open Alert", switch])
        self.assertEqual(steps[-1], switch)
        self.assertIn("critical urgent (rapid long)", detail)
        self.assertIn("normal signal (standard short)", detail)

    def test_a_critical_push_with_the_general_sound_but_not_its_vibration_fails(
        self,
    ):
        review, _ = self.review(
            [
                f"Alert played (sound on, vibration on): {GENERAL}",
                (
                    "Critical alert played (sound on, vibration on): sound=signal "
                    "volume=80% vibration=medium pattern=rapid length=long"
                ),
            ]
        )
        with self.assertRaisesRegex(CheckFailed, "switch off"):
            check_alert_critical(review)

    def test_a_critical_alert_of_its_own_with_another_vibration_fails(self):
        review, steps = self.review(
            [
                f"Alert played (sound on, vibration on): {GENERAL}",
                f"Critical alert played (sound on, vibration on): {GENERAL}",
                (
                    "Critical alert played (sound on, vibration on): sound=urgent "
                    "volume=100% vibration=strong pattern=standard length=short"
                ),
                f"Alert played (sound on, vibration on): {GENERAL}",
            ]
        )
        with self.assertRaisesRegex(CheckFailed, "switch on, a critical push"):
            check_alert_critical(review)
        self.assertEqual(steps[-1], "tap Different alert for critical events")

    def test_a_critical_push_with_the_switch_off_plays_the_general_alert(self):
        review, steps = self.review(
            [
                f"Alert played (sound on, vibration on): {GENERAL}",
                f"Critical alert played (sound on, vibration on): {OWN}",
            ]
        )
        with self.assertRaisesRegex(CheckFailed, "switch off"):
            check_alert_critical(review)
        self.assertNotIn("tap Different alert for critical events", steps)

    def test_the_switch_is_turned_off_again_when_the_check_fails(self):
        review, steps = self.review(
            [
                f"Alert played (sound on, vibration on): {GENERAL}",
                f"Critical alert played (sound on, vibration on): {GENERAL}",
                f"Critical alert played (sound on, vibration on): {GENERAL}",
                f"Alert played (sound on, vibration on): {GENERAL}",
            ]
        )
        with self.assertRaisesRegex(CheckFailed, "played signal"):
            check_alert_critical(review)
        self.assertEqual(steps[-1], "tap Different alert for critical events")

    def test_on_silent_critical_pushes_or_all_play_and_none_during_dnd(self):
        review, steps = self.review(
            [
                "Alert not played (silent mode): sound=signal",
                "Critical alert played (sound on, vibration on, as an alarm): x",
                "Alert played (sound on, vibration on, as an alarm): x",
                "Critical alert not played (do not disturb): x",
            ]
        )
        detail = check_alert_critical_quiet(review)
        self.assertEqual(self.severities, ["NORMAL", "CRITICAL", "NORMAL", "CRITICAL"])
        self.assertEqual(steps[0], "cmd audio set-ringer-mode SILENT")
        choices = [step for step in steps if step.startswith("tap ")]
        self.assertEqual(choices, ["tap All pushes", "tap Critical only"])
        self.assertLess(
            steps.index("publish normal on silent, all pushes"),
            steps.index("tap Critical only"),
        )
        self.assertLess(
            steps.index("tap Critical only"),
            steps.index("cmd audio set-ringer-mode NORMAL"),
        )
        self.assertEqual(steps[-1], "cmd notification set_dnd off")
        self.assertIn("All pushes", detail)

    def test_a_critical_push_quiet_on_silent_fails_and_the_ringer_is_restored(self):
        review, steps = self.review(
            [
                "Alert not played (silent mode): sound=signal",
                "Critical alert not played (silent mode): x",
            ]
        )
        with self.assertRaisesRegex(CheckFailed, "critical push"):
            check_alert_critical_quiet(review)
        self.assertEqual(steps[-1], "cmd audio set-ringer-mode NORMAL")

    def test_a_normal_push_quiet_with_all_pushes_fails_and_is_restored(self):
        review, steps = self.review(
            [
                "Alert not played (silent mode): sound=signal",
                "Critical alert played (sound on, vibration on, as an alarm): x",
                "Alert not played (silent mode): sound=signal",
            ]
        )
        with self.assertRaisesRegex(CheckFailed, "with All pushes"):
            check_alert_critical_quiet(review)
        self.assertIn("tap Critical only", steps)
        self.assertEqual(steps[-1], "cmd audio set-ringer-mode NORMAL")

    def test_a_critical_alert_during_dnd_fails(self):
        review, steps = self.review(
            [
                "Alert not played (silent mode): sound=signal",
                "Critical alert played (sound on, vibration on, as an alarm): x",
                "Alert played (sound on, vibration on, as an alarm): x",
                "Critical alert played (sound on, vibration on, as an alarm): x",
            ]
        )
        with self.assertRaisesRegex(CheckFailed, "during do-not-disturb"):
            check_alert_critical_quiet(review)
        self.assertEqual(steps[-1], "cmd notification set_dnd off")

    def test_a_phone_that_cannot_set_its_ringer_says_so(self):
        review, steps = self.review([])
        review.device.shell.side_effect = lambda command, **_: (
            steps.append(command) or "Unknown command: set-ringer-mode"
        )
        with self.assertRaisesRegex(CheckFailed, "by hand"):
            check_alert_critical_quiet(review)
        self.assertEqual(steps[-1], "cmd audio set-ringer-mode NORMAL")


def row(label: str, top: int) -> Node:
    return Node(label, "", (0, top, 1080, top + 150), False, APP_PACKAGE)


class SettingsGroupTest(unittest.TestCase):
    header = row("This device\nPixel 8 · Push notifications are on", 900)

    def review(self, screens: list[list[Node]]) -> tuple[Review, mock.Mock]:
        """A review whose Settings screen shows `screens` in turn, each dump
        the next until the last."""
        device = mock.Mock()
        device.scroll_to_upper_half.return_value = self.header
        device.nodes.side_effect = lambda: (
            screens.pop(0) if len(screens) > 1 else screens[0]
        )
        review = Review(fake_config(), device, mock.Mock())
        review.open_settings = lambda: None
        return review, device

    def test_a_row_below_the_header(self):
        nodes = [self.header, row("Push notifications are on", 1050)]
        self.assertEqual(group_row(nodes, self.header, PUSH_ON).bounds[1], 1050)

    def test_the_header_summary_is_not_a_row(self):
        self.assertIsNone(group_row([self.header], self.header, PUSH_ON))

    def test_rows_above_the_header_are_not_its_group(self):
        nodes = [row("Push notifications are on", 100), self.header]
        self.assertIsNone(group_row(nodes, self.header, PUSH_ON))

    def test_an_open_group_is_left_open(self):
        review, device = self.review(
            [[self.header, row("Push notifications are on", 1050)]]
        )
        review.open_group(DEVICE_GROUP)
        device.tap.assert_not_called()

    def test_a_folded_group_is_opened(self):
        review, device = self.review(
            [[self.header], [self.header, row("Push notifications are on", 1050)]]
        )
        found = review.open_group(DEVICE_GROUP)
        device.tap.assert_called_once_with(self.header)
        self.assertEqual(found.text, "Push notifications are on")

    def test_a_group_that_does_not_open_fails(self):
        review, _ = self.review([[self.header]])
        with (
            mock.patch("time.sleep"),
            mock.patch("time.monotonic", side_effect=[0, 5, 11]),
            self.assertRaisesRegex(CheckFailed, "not shown below"),
        ):
            review.open_group(DEVICE_GROUP)


class UiTest(unittest.TestCase):
    def test_nodes_after_the_dump_status_line(self):
        nodes = ui_nodes(sample("inbox.xml"))
        self.assertEqual(len(nodes), 5)
        settings = find_node(nodes, "Settings", exact=True)
        self.assertEqual(settings.bounds, (932, 147, 1058, 273))
        self.assertEqual(settings.center, (995, 210))

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


def fake_config() -> device_review.Config:
    return device_review.Config(
        serial="test-serial",
        server="http://localhost:8080",
        producer_key="shpk1_p",
        client_key="shck1_c",
        client_id="client-id",
        admin_token="a" * 40,
        output=Path("."),
        compose_dir=Path("."),
        compose_service="backend",
    )


class ServerTest(unittest.TestCase):
    def test_a_reset_connection_is_not_reachable(self):
        # As a backend starting behind Docker's port proxy answers.
        server = Server(fake_config())
        for error in (
            ConnectionResetError(104, "Connection reset by peer"),
            device_review.http.client.RemoteDisconnected("closed"),
        ):
            with (
                self.subTest(type(error).__name__),
                mock.patch("urllib.request.urlopen", side_effect=error),
            ):
                with self.assertRaises(CheckFailed):
                    server.unread()
                self.assertFalse(server.reachable())


class PushPreferencesTest(unittest.TestCase):
    """The order of the check's steps, with fakes recording what the device,
    the server and the clock are asked."""

    def run_check(self, pushed: set[str]) -> list[str]:
        steps: list[str] = []
        saved = {"enabled": True, "minimumSeverity": "NORMAL"}
        server = mock.Mock()
        server.own_registration.side_effect = lambda: {
            "pushPreferences": {"enabled": False} if "switch" in steps else saved
        }
        server.publish.side_effect = lambda title, **_: steps.append(title)
        server.set_push_preferences.side_effect = lambda p: steps.append(
            "restore" if p == saved else f"minimum {p['minimumSeverity']}"
        )
        device = mock.Mock()
        device.tap_label.side_effect = lambda *_, **__: steps.append("switch")
        device.app_notifications.side_effect = lambda title: (
            [title] if title in pushed else []
        )
        review = Review(fake_config(), device, server)
        review.title = lambda what: what
        review.open_settings = lambda: None
        self.addCleanup(lambda: self.assertEqual(steps[-1], "restore"))
        with mock.patch("time.sleep", side_effect=lambda _: steps.append("wait")):
            check_push_preferences(review)
        return steps

    def test_the_paused_event_is_dispatched_before_the_preferences_change(self):
        steps = self.run_check(pushed={"high"})
        paused, changed = steps.index("paused"), steps.index("minimum HIGH")
        self.assertIn("wait", steps[paused:changed])

    def test_a_push_while_paused_fails(self):
        with self.assertRaisesRegex(CheckFailed, "while push was off"):
            self.run_check(pushed={"paused", "high"})

    def test_a_push_below_the_minimum_fails(self):
        with self.assertRaisesRegex(CheckFailed, "below the minimum"):
            self.run_check(pushed={"low", "high"})


class PopupTest(unittest.TestCase):
    def run_check(self, differences: list[int]) -> list[str]:
        steps: list[str] = []
        device, server = mock.Mock(), mock.Mock()
        device.shell.side_effect = lambda command, **_: steps.append(command)
        device.scroll_to.side_effect = lambda label: label
        device.tap.side_effect = lambda node: steps.append(f"tap {node}")
        device.screenshot.side_effect = lambda name: steps.append(name)
        device.screen_size.return_value = (1080, 2340)
        review = Review(fake_config(), device, server)
        with (
            mock.patch("time.sleep", side_effect=lambda s: steps.append(f"wait {s}")),
            mock.patch("time.monotonic", side_effect=range(0, 1000, 3)),
            mock.patch.object(device_review, "pixels_differ", side_effect=differences),
        ):
            check_popup_over_other_app(review)
        return steps

    def test_the_baseline_waits_for_an_earlier_pop_up_to_go(self):
        steps = self.run_check([90000])
        before = steps.index("popup-before")
        self.assertIn(f"wait {device_review.QUIET_WAIT}", steps[:before])

    def test_the_screen_is_watched_from_the_publish_on(self):
        steps = self.run_check([64, 64, 90000])
        self.assertEqual(steps.count("popup-after"), 3)

    def test_a_brief_pop_up_is_enough(self):
        # As measured for Samsung's brief pop-up; the clock changes < 700.
        self.run_check([677, 18766])

    def test_no_pop_up(self):
        with self.assertRaisesRegex(CheckFailed, "no pop-up shown"):
            self.run_check([677] * 20)
