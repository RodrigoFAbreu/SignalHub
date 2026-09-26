import contextlib
import io
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

import release
from release import Bump, InvalidTitle, Version, classify


class ClassifyTest(unittest.TestCase):
    def test_bumps(self):
        cases = {
            "feat: add event ingestion": Bump.MINOR,
            "feat(api): add event ingestion": Bump.MINOR,
            "fix: prevent duplicate event delivery": Bump.PATCH,
            "docs: document producer API": Bump.PATCH,
            "refactor: simplify event persistence": Bump.PATCH,
            "chore(deps): bump actions/checkout": Bump.PATCH,
            "feat!: replace event schema": Bump.MAJOR,
            "fix(api)!: reject unsigned events": Bump.MAJOR,
            "refactor!: drop legacy endpoint": Bump.MAJOR,
            "feat: add event ingestion (#12)": Bump.MINOR,
        }
        for subject, expected in cases.items():
            with self.subTest(subject=subject):
                self.assertIs(classify(subject), expected)

    def test_rejects_non_conventional_titles(self):
        for subject in [
            "Add event ingestion",
            "feat add event ingestion",
            "feat:add event ingestion",
            "feat: ",
            "Feat: add event ingestion",
            "feature: add event ingestion",
            "feat(): add event ingestion",
            'Revert "feat: add event ingestion"',
        ]:
            with self.subTest(subject=subject), self.assertRaises(InvalidTitle):
                classify(subject)


class VersionTest(unittest.TestCase):
    def test_parse_tag(self):
        self.assertEqual(Version.parse_tag("v1.2.3"), Version(1, 2, 3))
        for tag in ["1.2.3", "v1.2", "v01.2.3", "v1.2.3-rc.1", "latest"]:
            with self.subTest(tag=tag):
                self.assertIsNone(Version.parse_tag(tag))

    def test_bump_0_x(self):
        base = Version(0, 27, 5)
        self.assertEqual(base.bump(Bump.PATCH), Version(0, 27, 6))
        self.assertEqual(base.bump(Bump.MINOR), Version(0, 28, 0))
        self.assertEqual(base.bump(Bump.MAJOR), Version(1, 0, 0))

    def test_bump_post_1_0(self):
        base = Version(1, 3, 4)
        self.assertEqual(base.bump(Bump.PATCH), Version(1, 3, 5))
        self.assertEqual(base.bump(Bump.MINOR), Version(1, 4, 0))
        self.assertEqual(base.bump(Bump.MAJOR), Version(2, 0, 0))

    def test_ordering_is_numeric(self):
        self.assertLess(Version(0, 9, 0), Version(0, 10, 0))


class NextVersionTest(unittest.TestCase):
    """Runs next_version() against real throwaway git repositories."""

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        cwd = os.getcwd()
        os.chdir(tmp.name)
        self.addCleanup(os.chdir, cwd)
        self.git("init", "--quiet", "--initial-branch=main")
        self.git("config", "user.name", "Test")
        self.git("config", "user.email", "test@example.com")
        self.git("config", "commit.gpgsign", "false")
        self.git("config", "tag.gpgsign", "false")

    def git(self, *args):
        subprocess.run(["git", *args], check=True, capture_output=True)

    def commit(self, subject):
        Path("file").write_text(subject)
        self.git("add", "file")
        self.git("commit", "--quiet", "-m", subject)

    def test_first_release_from_bootstrap_history(self):
        self.commit("initial")
        self.commit("feat: bootstrap repository")
        self.assertEqual(release.next_version(), Version(0, 1, 0))

    def test_single_unreleased_commit(self):
        self.commit("feat: bootstrap repository")
        self.git("tag", "v0.1.0")
        self.commit("fix: handle empty payload")
        self.assertEqual(release.next_version(), Version(0, 1, 1))

    def test_head_already_released(self):
        self.commit("feat: bootstrap repository")
        self.git("tag", "v0.1.0")
        self.assertIsNone(release.next_version())

    def test_catch_up_uses_highest_bump(self):
        self.commit("feat: bootstrap repository")
        self.git("tag", "v0.1.0")
        self.commit("fix: one")
        self.commit("feat: two")
        self.commit("docs: three")
        self.assertEqual(release.next_version(), Version(0, 2, 0))

    def test_uses_highest_version_tag_and_ignores_others(self):
        self.commit("feat: bootstrap repository")
        self.git("tag", "v0.9.0")
        self.commit("fix: one")
        self.git("tag", "v0.10.0")
        self.git("tag", "not-a-version")
        self.commit("fix: two")
        self.assertEqual(release.next_version(), Version(0, 10, 1))

    def test_breaking_change_on_0_x_releases_1_0_0(self):
        self.commit("feat: bootstrap repository")
        self.git("tag", "v0.27.5")
        self.commit("chore(release)!: promote SignalHub to v1.0.0")
        self.assertEqual(release.next_version(), Version(1, 0, 0))

    def test_non_breaking_changes_on_0_x_stay_below_1_0_0(self):
        self.commit("feat: bootstrap repository")
        self.git("tag", "v0.27.5")
        self.commit("fix: one")
        self.assertEqual(release.next_version(), Version(0, 27, 6))
        self.commit("feat: two")
        self.assertEqual(release.next_version(), Version(0, 28, 0))

    def test_after_1_0_0(self):
        self.commit("feat: bootstrap repository")
        self.git("tag", "v1.0.0")
        cases = [
            ("docs: one", Version(1, 0, 1)),
            ("feat: two", Version(1, 1, 0)),
            ("fix(api)!: three", Version(2, 0, 0)),
        ]
        for subject, expected in cases:
            with self.subTest(subject=subject):
                self.commit(subject)
                self.assertEqual(release.next_version(), expected)
                self.git("tag", str(expected))

    def test_non_conventional_subject_on_main_is_patch(self):
        self.commit("feat: bootstrap repository")
        self.git("tag", "v0.1.0")
        self.commit("Update README")
        self.assertEqual(release.next_version(), Version(0, 1, 1))


class MainTest(unittest.TestCase):
    def test_check_title_exit_codes(self):
        self.assertEqual(release.main(["check-title", "feat: add thing"]), 0)
        self.assertEqual(release.main(["check-title", "add thing"]), 1)
        self.assertEqual(release.main(["bogus"]), 2)

    def test_check_title_reports_breaking_as_major(self):
        with contextlib.redirect_stdout(io.StringIO()) as out:
            release.main(["check-title", "feat!: replace event schema"])
        self.assertEqual(out.getvalue(), "Valid title. Release impact: major\n")


if __name__ == "__main__":
    unittest.main()
