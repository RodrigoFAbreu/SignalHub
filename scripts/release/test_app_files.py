"""Tests of app_files.py on recorded tool output.

The build itself needs Flutter, the Android SDK and a key, so CI's client job
runs it with a throwaway key (as the release does with SignalHub's); these
tests need none of them.
"""

import re
import tempfile
import unittest
import zipfile
from pathlib import Path

from app_files import (
    AppFilesError,
    build_command,
    build_tool,
    check_identity,
    check_revision,
    check_signer,
    file_name,
    parse_badging,
    parse_keystore_digest,
    parse_signers,
    signing_settings,
    version_code,
)

ROOT = Path(__file__).resolve().parents[2]
REVISION = "f22a9aa79a44090fada538cdb124a0fe61c03d63"
DIGEST = "81c4e47b0f46bee7a90e71b0fe800934db5efdebcd5c97c99c65fd0363908006"

BADGING = """\
package: name='io.github.rodrigofabreu.signalhub' versionCode='1007000' \
versionName='1.7.0' platformBuildVersionName='16' platformBuildVersionCode='36' \
compileSdkVersion='36' compileSdkVersionCodename='16'
minSdkVersion:'24'
targetSdkVersion:'36'
application-label:'SignalHub'
application: label='SignalHub' icon='res/mipmap-mdpi-v4/ic_launcher.png'
"""

# Recorded from the client job's build, with SignalHub's certificate.
APKSIGNER = f"""\
Verifies
Verified using v1 scheme (JAR signing): false
Verified using v2 scheme (APK Signature Scheme v2): true
Verified using v3 scheme (APK Signature Scheme v3): false
Verified using v3.1 scheme (APK Signature Scheme v3.1): false
Verified using v3.2 scheme (APK Signature Scheme v3.2): false
Verified using v4 scheme (APK Signature Scheme v4): false
Verified for SourceStamp: false
Number of signers: 1
V2 Signer: certificate DN: CN=SignalHub
V2 Signer: certificate SHA-256 digest: {DIGEST}
V2 Signer: certificate SHA-1 digest: adb8ab7c67e0c5235136b8b15b0b31041d1d7519
V2 Signer: certificate MD5 digest: ffd66f3a85a5fb1ea58598cfc64ace7e
V2 Signer: key algorithm: RSA
V2 Signer: key size (bits): 2048
V2 Signer: public key SHA-256 digest: \
ed24d1b38377b54156849cc1dd896adee1820839c8da48e758f7469288d49da9
V2 Signer: public key SHA-1 digest: d4d09830373cb7a679ff8fab8045970a28f8e256
V2 Signer: public key MD5 digest: 6c92676b4ed768651fb49bd0285580dc
"""

KEYTOOL = """\
Alias name: signalhub
Creation date: Sep 27, 2026
Entry type: PrivateKeyEntry
Certificate chain length: 1
Certificate[1]:
Owner: CN=SignalHub
Issuer: CN=SignalHub
Certificate fingerprints:
\t SHA1: B4:D5:BE:34:37:4F:75:99:2E:C5:4F:F7:45:0D:7E:DD:59:83:D5:12
\t SHA256: 81:C4:E4:7B:0F:46:BE:E7:A9:0E:71:B0:FE:80:09:34:DB:5E:FD:EB:CD:5C:97:C9:9C:65:FD:03:63:90:80:06
Signature algorithm name: SHA384withRSA
"""


class VersionCodeTest(unittest.TestCase):
    def test_follows_the_documented_rule(self):
        self.assertEqual(version_code("1.7.0"), 1_007_000)
        self.assertEqual(version_code("2.0.13"), 2_000_013)
        self.assertEqual(version_code("12.345.678"), 12_345_678)

    def test_grows_with_every_release(self):
        releases = ["1.7.0", "1.7.1", "1.7.999", "1.8.0", "1.999.999", "2.0.0"]
        codes = [version_code(version) for version in releases]
        self.assertEqual(codes, sorted(set(codes)))

    def test_is_above_every_local_build(self):
        # Local builds take pubspec.yaml's build number, 1.
        self.assertGreater(version_code("1.0.0"), 1)

    def test_the_ci_test_version_gets_one(self):
        self.assertEqual(version_code("0.0.0-ci"), 1)

    def test_refuses_versions_the_rule_cannot_order(self):
        for version in ("1.1000.0", "1.0.1000", "0.0.0", "2100.0.1", "3000.0.0"):
            with self.subTest(version=version), self.assertRaises(AppFilesError):
                version_code(version)

    def test_refuses_what_is_not_a_version(self):
        for version in ("", "v1.2.3", "1.2", "1.2.3-rc1", "1.2.3+ci", "1.2.3\n"):
            with self.subTest(version=version), self.assertRaises(AppFilesError):
                version_code(version)


class BuildCommandTest(unittest.TestCase):
    def test_sets_the_version_and_commit(self):
        command = build_command("1.7.0", REVISION)
        self.assertEqual(command[:4], ["flutter", "build", "apk", "--release"])
        self.assertIn("--build-name=1.7.0", command)
        self.assertIn("--build-number=1007000", command)
        self.assertIn("--dart-define=SIGNALHUB_VERSION=1.7.0", command)
        self.assertIn(f"--dart-define=SIGNALHUB_REVISION={REVISION}", command)

    def test_compiles_in_no_firebase_options(self):
        # The released app reads its server's push options (R23).
        command = build_command("1.7.0", REVISION)
        self.assertFalse(
            [part for part in command if part.startswith("--dart-define-from-file")]
        )
        self.assertFalse([part for part in command if "FIREBASE" in part])

    def test_refuses_what_is_not_a_full_commit(self):
        for revision in ("", "f22a9aa", REVISION.upper(), REVISION + "0", "HEAD"):
            with self.subTest(revision=revision), self.assertRaises(AppFilesError):
                build_command("1.7.0", revision)

    def test_names_the_file_as_the_roadmap_does(self):
        self.assertEqual(file_name("1.7.0"), "SignalHub-1.7.0.apk")


class SigningSettingsTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.keystore = Path(directory.name) / "release.jks"
        self.keystore.write_bytes(b"keystore")
        self.environ = {
            "ANDROID_RELEASE_KEYSTORE": str(self.keystore),
            "ANDROID_RELEASE_KEYSTORE_PASSWORD": "store secret",
            "ANDROID_RELEASE_KEY_ALIAS": "signalhub",
            "ANDROID_RELEASE_KEY_PASSWORD": "key secret",
        }

    def test_returns_the_keystore(self):
        self.assertEqual(signing_settings(self.environ), self.keystore)

    def test_refuses_to_build_without_every_setting(self):
        for name in self.environ:
            for environ in (
                {**self.environ, name: ""},
                {key: value for key, value in self.environ.items() if key != name},
            ):
                with self.subTest(name=name, environ=environ):
                    with self.assertRaises(AppFilesError) as raised:
                        signing_settings(environ)
                    self.assertIn(name, str(raised.exception))

    def test_refuses_a_missing_keystore(self):
        self.keystore.unlink()
        with self.assertRaises(AppFilesError):
            signing_settings(self.environ)

    def test_never_names_a_password(self):
        with self.assertRaises(AppFilesError) as raised:
            signing_settings({**self.environ, "ANDROID_RELEASE_KEY_ALIAS": ""})
        self.assertNotIn("secret", str(raised.exception))


class BuildToolTest(unittest.TestCase):
    def test_takes_the_newest_build_tools(self):
        with tempfile.TemporaryDirectory() as sdk:
            for version in ("34.0.0", "36.1.0", "9.0.0", "36.0.0"):
                tool = Path(sdk) / "build-tools" / version / "apksigner"
                tool.parent.mkdir(parents=True)
                tool.touch()
            self.assertEqual(
                build_tool("apksigner", {"ANDROID_HOME": sdk}),
                Path(sdk) / "build-tools" / "36.1.0" / "apksigner",
            )

    def test_refuses_an_sdk_without_it(self):
        with tempfile.TemporaryDirectory() as sdk, self.assertRaises(AppFilesError):
            build_tool("apksigner", {"ANDROID_HOME": sdk})
        with self.assertRaises(AppFilesError):
            build_tool("apksigner", {})


class IdentityTest(unittest.TestCase):
    def test_reads_the_badging(self):
        self.assertEqual(
            parse_badging(BADGING),
            {
                "package": "io.github.rodrigofabreu.signalhub",
                "versionCode": "1007000",
                "versionName": "1.7.0",
                "debuggable": "no",
            },
        )

    def test_accepts_the_release(self):
        check_identity(parse_badging(BADGING), "1.7.0")

    def test_refuses_another_version_or_package(self):
        for badging, version in (
            (BADGING, "1.7.1"),
            (BADGING.replace("1007000", "1"), "1.7.0"),
            (BADGING.replace("rodrigofabreu.signalhub", "example.app"), "1.7.0"),
        ):
            with (
                self.subTest(badging=badging, version=version),
                self.assertRaises(AppFilesError),
            ):
                check_identity(parse_badging(badging), version)

    def test_refuses_a_debuggable_app(self):
        badging = parse_badging(BADGING + "application-debuggable\n")
        with self.assertRaises(AppFilesError):
            check_identity(badging, "1.7.0")

    def test_refuses_output_without_a_package(self):
        with self.assertRaises(AppFilesError):
            parse_badging("minSdkVersion:'24'\n")


class SignerTest(unittest.TestCase):
    def test_reads_the_signer(self):
        self.assertEqual(
            parse_signers(APKSIGNER), {"digest": DIGEST, "dn": "CN=SignalHub"}
        )

    def test_reads_the_keystore_digest_as_apksigner_prints_it(self):
        self.assertEqual(parse_keystore_digest(KEYTOOL), DIGEST)

    def test_accepts_the_given_key(self):
        check_signer(parse_signers(APKSIGNER), DIGEST)

    def test_refuses_another_key(self):
        with self.assertRaises(AppFilesError):
            check_signer(parse_signers(APKSIGNER), "0" * 64)

    def test_refuses_the_debug_key(self):
        output = APKSIGNER.replace("CN=SignalHub", "CN=Android Debug, O=Android, C=US")
        with self.assertRaises(AppFilesError):
            check_signer(parse_signers(output), DIGEST)

    def test_refuses_an_apk_without_a_v2_or_v3_signature(self):
        output = APKSIGNER.replace("v2): true", "v2): false")
        with self.assertRaises(AppFilesError):
            parse_signers(output)

    def test_reads_the_older_signer_lines(self):
        output = APKSIGNER.replace("V2 Signer:", "Signer #1")
        self.assertEqual(
            parse_signers(output), {"digest": DIGEST, "dn": "CN=SignalHub"}
        )

    def test_refuses_a_second_key(self):
        output = APKSIGNER + (
            "Signer (minSdkVersion=33, maxSdkVersion=2147483647) certificate SHA-256"
            " digest: " + "1" * 64 + "\n"
        )
        with self.assertRaises(AppFilesError):
            parse_signers(output)

    def test_refuses_output_without_a_certificate(self):
        with self.assertRaises(AppFilesError):
            parse_signers(APKSIGNER.split("V2 Signer")[0])

    def test_refuses_more_than_one_signer(self):
        with self.assertRaises(AppFilesError):
            parse_signers(APKSIGNER.replace("signers: 1", "signers: 2"))

    def test_refuses_keytool_output_without_a_fingerprint(self):
        with self.assertRaises(AppFilesError):
            parse_keystore_digest(KEYTOOL.replace("SHA256", "SHA512"))


class RevisionTest(unittest.TestCase):
    def apk(self, libraries: dict[str, bytes]) -> Path:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / "app.apk"
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr("AndroidManifest.xml", b"manifest")
            for name, content in libraries.items():
                archive.writestr(name, content)
        return path

    def test_accepts_the_commit_in_every_abi(self):
        code = b"\x00SignalHub development build\x00" + REVISION.encode() + b"\x00"
        check_revision(
            self.apk({"lib/arm64-v8a/libapp.so": code, "lib/x86_64/libapp.so": code}),
            REVISION,
        )

    def test_refuses_an_abi_without_it(self):
        apk = self.apk(
            {
                "lib/arm64-v8a/libapp.so": REVISION.encode(),
                "lib/x86_64/libapp.so": b"no commit",
            }
        )
        with self.assertRaises(AppFilesError):
            check_revision(apk, REVISION)

    def test_refuses_an_apk_without_dart_code(self):
        with self.assertRaises(AppFilesError):
            check_revision(self.apk({}), REVISION)


class GradleTest(unittest.TestCase):
    """The app's Gradle build reads the key from the variables the script checks."""

    def test_signs_with_the_release_key_when_given(self):
        gradle = (ROOT / "client" / "android" / "app" / "build.gradle.kts").read_text()
        for name in (
            "ANDROID_RELEASE_KEYSTORE",
            "ANDROID_RELEASE_KEYSTORE_PASSWORD",
            "ANDROID_RELEASE_KEY_ALIAS",
            "ANDROID_RELEASE_KEY_PASSWORD",
        ):
            self.assertIn(f'"{name}"', gradle)


class FlutterVersionTest(unittest.TestCase):
    def test_the_release_builds_with_the_flutter_ci_tests(self):
        def pin(workflow):
            text = (ROOT / ".github" / "workflows" / workflow).read_text()
            return re.search(r"^  FLUTTER_VERSION: (\S+)", text, re.MULTILINE).group(1)

        self.assertEqual(pin("release.yml"), pin("ci.yml"))


if __name__ == "__main__":
    unittest.main()
