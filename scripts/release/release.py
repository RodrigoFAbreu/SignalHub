"""Release versioning for SignalHub.

Every commit on `main` is a release. This script derives the next semantic
version from Conventional Commit subjects. See docs/development.md for the
policy it implements.

Usage:
    release.py check-title TITLE   Validate a PR title and print its release impact.
    release.py next-version        Print the version to release for HEAD, or nothing
                                   if HEAD is already released.

Only the standard library is used so the script runs on any runner without setup.
"""

from __future__ import annotations

import re
import subprocess
import sys
from dataclasses import dataclass
from enum import IntEnum

TYPES = (
    "feat",
    "fix",
    "perf",
    "refactor",
    "docs",
    "test",
    "build",
    "ci",
    "chore",
    "style",
    "revert",
)

SUBJECT_RE = re.compile(
    r"^(?P<type>[a-z]+)(?:\((?P<scope>[a-z0-9._/-]+)\))?(?P<breaking>!)?: (?P<description>\S.*)$"
)
TAG_RE = re.compile(r"^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")


class Bump(IntEnum):
    PATCH = 1
    MINOR = 2
    MAJOR = 3


@dataclass(frozen=True, order=True)
class Version:
    major: int
    minor: int
    patch: int

    @classmethod
    def parse_tag(cls, tag: str) -> Version | None:
        match = TAG_RE.match(tag)
        if match is None:
            return None
        return cls(*(int(part) for part in match.groups()))

    def bump(self, bump: Bump) -> Version:
        # Pre-1.0: a breaking change bumps minor. 1.0.0 is a deliberate decision,
        # never an automatic side effect of a `!` in a commit title.
        if bump is Bump.MAJOR and self.major == 0:
            bump = Bump.MINOR
        if bump is Bump.MAJOR:
            return Version(self.major + 1, 0, 0)
        if bump is Bump.MINOR:
            return Version(self.major, self.minor + 1, 0)
        return Version(self.major, self.minor, self.patch + 1)

    def __str__(self) -> str:
        return f"v{self.major}.{self.minor}.{self.patch}"


class InvalidTitle(ValueError):
    pass


def classify(subject: str) -> Bump:
    """Return the bump for a Conventional Commit subject, or raise InvalidTitle."""
    match = SUBJECT_RE.match(subject.strip())
    if match is None:
        raise InvalidTitle(
            f"not a Conventional Commit title: {subject!r} "
            "(expected 'type(optional-scope)!: description')"
        )
    if match["type"] not in TYPES:
        raise InvalidTitle(
            f"unknown type {match['type']!r}; allowed: {', '.join(TYPES)}"
        )
    if match["breaking"]:
        return Bump.MAJOR
    if match["type"] == "feat":
        return Bump.MINOR
    return Bump.PATCH


def classify_lenient(subject: str) -> Bump:
    """Classify a commit already on main; non-conforming subjects count as patch.

    PR title validation is the gate. A non-conforming subject on main means that
    gate was bypassed; blocking every future release would be worse than a
    conservative patch bump, so warn and continue.
    """
    try:
        return classify(subject)
    except InvalidTitle as error:
        print(f"::warning::{error}; treating as patch", file=sys.stderr)
        return Bump.PATCH


def git(*args: str) -> str:
    return subprocess.run(
        ["git", *args], check=True, capture_output=True, text=True
    ).stdout


def latest_release() -> tuple[str, Version] | None:
    """Return the highest version tag reachable from HEAD."""
    tags = [
        (tag, version)
        for tag in git("tag", "--merged", "HEAD").split()
        if (version := Version.parse_tag(tag)) is not None
    ]
    return max(tags, key=lambda item: item[1], default=None)


def next_version() -> Version | None:
    """Return the version for HEAD, or None if nothing is unreleased.

    Normally exactly one commit (the squash-merged PR) is unreleased. If an
    earlier release run failed or was superseded, all unreleased commits are
    released together at HEAD with the highest bump among them.
    """
    latest = latest_release()
    if latest is None:
        base, revisions = Version(0, 0, 0), "HEAD"
    else:
        tag, base = latest
        revisions = f"{tag}..HEAD"
    subjects = git("log", "--first-parent", "--format=%s", revisions).splitlines()
    if not subjects:
        return None
    return base.bump(max(classify_lenient(subject) for subject in subjects))


def main(argv: list[str]) -> int:
    if len(argv) == 2 and argv[0] == "check-title":
        try:
            bump = classify(argv[1])
        except InvalidTitle as error:
            print(f"error: {error}", file=sys.stderr)
            return 1
        impact = bump.name.lower()
        if bump is Bump.MAJOR:
            impact += " (bumps minor while the version is below 1.0.0)"
        print(f"Valid title. Release impact: {impact}")
        return 0
    if argv == ["next-version"]:
        version = next_version()
        if version is not None:
            print(version)
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
