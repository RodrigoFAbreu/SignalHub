"""Builds a release's Android app, SignalHub-VERSION.apk (client/README.md).

A release-mode APK built from the commit in client/, signed with the key the
environment names, with the release's version as Android's versionName, a
versionCode derived from it (version_code), and the version and commit
compiled in as the defines the *This device* screen shows (BuildIdentity).
No Firebase options are compiled in: the app reads its server's (R23).

Before printing, the APK is checked, so a release never attaches an app that
would identify as something else or be signed by another key: package name,
versionName, versionCode, not debuggable, the commit in the compiled Dart
code, a valid APK signature by exactly one signer, and that signer being the
certificate of the given key (so never the debug key).

Usage:
    app_files.py VERSION REVISION DIRECTORY
        Writes DIRECTORY/SignalHub-VERSION.apk and prints its path, then the
        SHA-256 digest of its signing certificate. Needs Flutter on the PATH,
        the Android SDK (ANDROID_HOME) with build-tools, keytool, and:

        ANDROID_RELEASE_KEYSTORE           path of the keystore
        ANDROID_RELEASE_KEYSTORE_PASSWORD  its password
        ANDROID_RELEASE_KEY_ALIAS          the key's alias
        ANDROID_RELEASE_KEY_PASSWORD       the key's password

        Passwords are only ever read from the environment, never passed as
        arguments, and never printed.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "client"
BUILT_APK = CLIENT / "build" / "app" / "outputs" / "flutter-apk" / "app-release.apk"

PACKAGE = "io.github.rodrigofabreu.signalhub"

# A release version (1.2.3) or the CI test version (0.0.0-ci).
VERSION = re.compile(r"([0-9]+)\.([0-9]+)\.([0-9]+)(-ci)?")
REVISION = re.compile(r"[0-9a-f]{40}")

SIGNING = (
    "ANDROID_RELEASE_KEYSTORE",
    "ANDROID_RELEASE_KEYSTORE_PASSWORD",
    "ANDROID_RELEASE_KEY_ALIAS",
    "ANDROID_RELEASE_KEY_PASSWORD",
)

# Android refuses larger version codes.
MAX_VERSION_CODE = 2_100_000_000


class AppFilesError(Exception):
    pass


def version_code(version: str) -> int:
    """Android's versionCode for a SignalHub version.

    MAJOR * 1000000 + MINOR * 1000 + PATCH, so it grows with every release
    while MINOR and PATCH stay below 1000. The CI test version gets 1: it is
    never installed over a release.
    """
    match = VERSION.fullmatch(version)
    if not match:
        raise AppFilesError(f"not a version: {version!r}")
    if match.group(4):
        return 1
    major, minor, patch = (int(part) for part in match.group(1, 2, 3))
    if minor >= 1000 or patch >= 1000:
        raise AppFilesError(
            f"no versionCode rule for {version}: MINOR or PATCH over 999"
        )
    code = major * 1_000_000 + minor * 1_000 + patch
    if not 0 < code <= MAX_VERSION_CODE:
        raise AppFilesError(f"no valid versionCode for {version}")
    return code


def file_name(version: str) -> str:
    return f"SignalHub-{version}.apk"


def build_command(version: str, revision: str) -> list[str]:
    """The release build; deliberately without --dart-define-from-file, so
    no Firebase options are compiled in."""
    if not REVISION.fullmatch(revision):
        raise AppFilesError(f"not a full commit: {revision!r}")
    return [
        "flutter",
        "build",
        "apk",
        "--release",
        f"--build-name={version}",
        f"--build-number={version_code(version)}",
        f"--dart-define=SIGNALHUB_VERSION={version}",
        f"--dart-define=SIGNALHUB_REVISION={revision}",
    ]


def signing_settings(environ: dict[str, str]) -> Path:
    """The keystore, once every signing variable is set."""
    missing = [name for name in SIGNING if not environ.get(name)]
    if missing:
        raise AppFilesError(f"not set: {', '.join(missing)}")
    keystore = Path(environ["ANDROID_RELEASE_KEYSTORE"])
    if not keystore.is_file():
        raise AppFilesError("ANDROID_RELEASE_KEYSTORE names no file")
    return keystore


def build_tool(name: str, environ: dict[str, str]) -> Path:
    """The tool of the newest build-tools of the Android SDK."""
    sdk = environ.get("ANDROID_HOME") or environ.get("ANDROID_SDK_ROOT")
    if not sdk:
        raise AppFilesError("ANDROID_HOME is not set")
    versions = sorted(
        (Path(sdk) / "build-tools").glob("*/" + name),
        key=lambda path: [
            int(part) for part in re.findall(r"[0-9]+", path.parent.name)
        ],
    )
    if not versions:
        raise AppFilesError(f"no {name} in {sdk}/build-tools")
    return versions[-1]


def parse_badging(output: str) -> dict[str, str]:
    """Package name, versionCode and versionName from `aapt2 dump badging`."""
    match = re.search(
        r"^package: name='([^']*)' versionCode='([^']*)' versionName='([^']*)'",
        output,
        re.MULTILINE,
    )
    if not match:
        raise AppFilesError("aapt2 printed no package line")
    return {
        "package": match.group(1),
        "versionCode": match.group(2),
        "versionName": match.group(3),
        "debuggable": "yes"
        if re.search(r"^application-debuggable", output, re.MULTILINE)
        else "no",
    }


def parse_signers(output: str) -> dict[str, str]:
    """The one signer's certificate from `apksigner verify --print-certs --verbose`."""
    if not re.search(
        r"^Verified using v[23] scheme \(.*\): true$", output, re.MULTILINE
    ):
        raise AppFilesError("the APK has no valid v2 or v3 signature")
    signers = re.search(r"^Number of signers: ([0-9]+)$", output, re.MULTILINE)
    if not signers or signers.group(1) != "1":
        raise AppFilesError("the APK is not signed by exactly one signer")
    digest = re.search(
        r"^Signer #1 certificate SHA-256 digest: ([0-9a-f]{64})$", output, re.MULTILINE
    )
    dn = re.search(r"^Signer #1 certificate DN: (.*)$", output, re.MULTILINE)
    if not digest or not dn:
        raise AppFilesError("apksigner printed no certificate")
    return {"digest": digest.group(1), "dn": dn.group(1)}


def parse_keystore_digest(output: str) -> str:
    """The certificate's SHA-256 digest from `keytool -list -v`, as apksigner prints it."""
    match = re.search(
        r"^\s*SHA256: ((?:[0-9A-F]{2}:){31}[0-9A-F]{2})$", output, re.MULTILINE
    )
    if not match:
        raise AppFilesError("keytool printed no SHA-256 fingerprint")
    return match.group(1).replace(":", "").lower()


def check_identity(badging: dict[str, str], version: str) -> None:
    expected = {
        "package": PACKAGE,
        "versionCode": str(version_code(version)),
        "versionName": version,
        "debuggable": "no",
    }
    for field, value in expected.items():
        if badging[field] != value:
            raise AppFilesError(
                f"the APK's {field} is {badging[field]!r}, not {value!r}"
            )


def check_signer(signer: dict[str, str], key_digest: str) -> None:
    if "CN=Android Debug" in signer["dn"]:
        raise AppFilesError("the APK is signed with a debug key")
    if signer["digest"] != key_digest:
        raise AppFilesError("the APK is not signed by the given key")


def check_revision(apk: Path, revision: str) -> None:
    """The commit is compiled into the Dart code of every ABI."""
    with zipfile.ZipFile(apk) as archive:
        libraries = [name for name in archive.namelist() if name.endswith("/libapp.so")]
        if not libraries:
            raise AppFilesError("the APK has no compiled Dart code")
        for name in libraries:
            if revision.encode() not in archive.read(name):
                raise AppFilesError(f"{name} does not carry the commit")


def run(command: list[str], quiet: bool = False, **kwargs) -> str:
    try:
        return subprocess.run(
            command, check=True, capture_output=True, text=True, **kwargs
        ).stdout
    except subprocess.CalledProcessError as error:
        if not quiet:
            sys.stderr.write(error.stdout + error.stderr)
        raise


def build(
    version: str, revision: str, directory: Path, environ: dict[str, str]
) -> tuple[Path, str]:
    command = build_command(version, revision)
    keystore = signing_settings(environ)
    apksigner = build_tool("apksigner", environ)
    aapt2 = build_tool("aapt2", environ)
    subprocess.run(command, cwd=CLIENT, check=True, stdout=sys.stderr)
    apk = directory / file_name(version)
    shutil.copyfile(BUILT_APK, apk)

    check_identity(
        parse_badging(run([str(aapt2), "dump", "badging", str(apk)])), version
    )
    check_revision(apk, revision)
    signer = parse_signers(
        run([str(apksigner), "verify", "--print-certs", "--verbose", str(apk)])
    )
    key_digest = parse_keystore_digest(
        run(
            [
                "keytool",
                "-list",
                "-v",
                "-keystore",
                str(keystore),
                "-alias",
                environ["ANDROID_RELEASE_KEY_ALIAS"],
                "-storepass:env",
                "ANDROID_RELEASE_KEYSTORE_PASSWORD",
            ],
            # Its output names the key; only the digest is used.
            quiet=True,
            env=environ,
        )
    )
    check_signer(signer, key_digest)
    return apk, signer["digest"]


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    version, revision, directory = argv
    try:
        apk, digest = build(version, revision, Path(directory), dict(os.environ))
    except (AppFilesError, subprocess.CalledProcessError) as error:
        print(f"app_files.py: {error}", file=sys.stderr)
        return 1
    print(apk)
    print(digest)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
