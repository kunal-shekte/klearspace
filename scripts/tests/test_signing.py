import hashlib
import io
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import notarize
import signing

TEAM = "ABCDE12345"
SHA = "A" * 40
NAME = f"Developer ID Application: Example Developer ({TEAM})"
APP_ID = "11111111-1111-4111-8111-111111111111"
DMG_ID = "22222222-2222-4222-8222-222222222222"
VERSION = (notarize.ROOT / "VERSION").read_text().strip()
LISTING = f'  1) {SHA} "{NAME}"\n  2) {"B" * 40} "Apple Development: Example Developer ({TEAM})"'


class IdentityTests(unittest.TestCase):
    def test_matches_name_or_hash_for_the_explicit_team(self):
        self.assertEqual(signing.resolve_identity(NAME, TEAM, LISTING), SHA)
        self.assertEqual(signing.resolve_identity(SHA.lower(), TEAM, LISTING), SHA)

    def test_refuses_development_adhoc_installer_and_other_teams(self):
        for request in ["-", "B" * 40, "Developer ID Installer: Example Developer (ABCDE12345)", ""]:
            with self.assertRaises(ValueError):
                signing.resolve_identity(request, TEAM, LISTING)
        with self.assertRaises(ValueError):
            signing.resolve_identity(NAME, "OTHER12345", LISTING)
        with self.assertRaises(ValueError):
            signing.resolve_identity(NAME, "", LISTING)

    def test_rejects_ambiguous_names(self):
        with self.assertRaises(ValueError):
            signing.resolve_identity(NAME, TEAM, LISTING + f'\n3) {"C" * 40} "{NAME}"')

    def test_signature_requires_team_runtime_timestamp_and_no_debug_entitlement(self):
        metadata = f"Authority={NAME}\nTeamIdentifier={TEAM}\nTimestamp=Oct 17, 2026\nCodeDirectory flags=0x10000(runtime)\n"
        signing.validate_metadata(metadata, TEAM, True, {})
        for value in [metadata.replace(TEAM, "OTHER12345"), metadata.replace("Timestamp=", "NoTime="), metadata.replace("runtime", "adhoc")]:
            with self.assertRaises(ValueError):
                signing.validate_metadata(value, TEAM, True, {})
        with self.assertRaises(ValueError):
            signing.validate_metadata(metadata, TEAM, True, {"com.apple.security.get-task-allow": True})


class PipelineTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.output = Path(self.temporary.name)
        self.submits = []
        self.app_status = "Accepted"
        self.dmg_status = "Accepted"
        self.interrupt = False
        self.commands = []
        self.env = patch.dict(os.environ, {"KLEARSPACE_TEAM_ID": TEAM, "KLEARSPACE_SIGNING_IDENTITY": NAME})
        self.env.start()
        self.identity = patch.object(signing, "selected_identity", return_value=SHA)
        self.identity.start()
        self.verifier = patch.object(signing, "verify")
        self.verifier.start()
        self.runner = patch.object(notarize, "command", side_effect=self.fake_command)
        self.runner.start()
        self.notary = patch.object(notarize.Pipeline, "notary", side_effect=self.fake_notary)
        self.notary.start()
        self.console = patch("sys.stdout", new_callable=io.StringIO)
        self.console.start()

    def tearDown(self):
        patch.stopall()
        self.temporary.cleanup()

    def fake_command(self, args, capture=False):
        args = [str(x) for x in args]
        self.commands.append(args)
        if "rev-parse" in args:
            return "fixture-commit\n"
        if "status" in args:
            return ""
        if args[0].endswith("build.sh"):
            app = self.output / "Klearspace.app"
            app.mkdir(exist_ok=True)
        if args[0] == "ditto":
            Path(args[-1]).write_bytes(b"signed-app-fixture")
        if args[0].endswith("package-dmg.sh"):
            (self.output / f"Klearspace-{VERSION}-arm64.dmg").write_bytes(b"signed-dmg-fixture")
            (self.output / "SHA256SUMS.txt").write_text("provisional checksum")
        if args[:2] == ["lipo", "-archs"]:
            return "arm64\n"
        if args[:3] == ["xcrun", "stapler", "staple"] and args[-1].endswith(".dmg"):
            path = Path(args[-1])
            if not path.read_bytes().endswith(b"ticket"):
                path.write_bytes(path.read_bytes() + b"ticket")
        return ""

    def fake_notary(self, operation, *args):
        if operation == "history":
            return {"history": []}
        if operation == "submit":
            self.submits.append(str(args[0]))
            if self.interrupt:
                self.interrupt = False
                raise RuntimeError("connection interrupted before response")
            return {"id": APP_ID if str(args[0]).endswith(".zip") else DMG_ID}
        if operation == "info":
            return {"status": self.app_status if args[0] == APP_ID else self.dmg_status}
        raise AssertionError(operation)

    def pipeline(self):
        return notarize.Pipeline(self.output, "fixture-profile")

    def test_complete_flow_checksums_final_stapled_bytes(self):
        self.assertEqual(self.pipeline().execute(), 0)
        self.assertEqual(len(self.submits), 2)
        dmg = self.output / f"Klearspace-{VERSION}-arm64.dmg"
        expected = hashlib.sha256(dmg.read_bytes()).hexdigest()
        self.assertTrue(dmg.read_bytes().endswith(b"ticket"))
        self.assertIn(expected, (self.output / "SHA256SUMS.txt").read_text())
        self.assertTrue(any(command[0] == "spctl" and "execute" in command for command in self.commands))
        self.assertTrue(any(command[0] == "spctl" and "open" in command for command in self.commands))

    def test_pending_requests_resume_without_duplicate_uploads(self):
        self.app_status = "In Progress"
        self.assertEqual(self.pipeline().execute(), 2)
        self.assertEqual(len(self.submits), 1)
        self.app_status = "Accepted"; self.dmg_status = "In Progress"
        self.assertEqual(self.pipeline().execute(), 2)
        self.assertFalse((self.output / "SHA256SUMS.txt").exists())
        self.dmg_status = "Accepted"
        self.assertEqual(self.pipeline().execute(), 0)
        self.assertEqual(self.pipeline().execute(), 0)
        self.assertEqual(len(self.submits), 2)

    def test_interrupted_upload_requires_explicit_id_recovery(self):
        self.interrupt = True
        with self.assertRaises(RuntimeError):
            self.pipeline().execute()
        with self.assertRaisesRegex(ValueError, "did not record an ID"):
            self.pipeline().execute()
        self.assertEqual(len(self.submits), 1)
        self.assertEqual(self.pipeline().execute(recover_app=APP_ID), 0)
        self.assertEqual(len(self.submits), 2)  # app once, then DMG once

    def test_changed_submitted_archive_is_refused(self):
        self.app_status = "In Progress"
        self.pipeline().execute()
        archive = self.output / ".notarization/Klearspace-notarization.zip"
        archive.write_bytes(b"unexpected mutation")
        with self.assertRaisesRegex(ValueError, "changed or disappeared"):
            self.pipeline().execute()
        self.assertEqual(len(self.submits), 1)

    def test_apple_rejection_never_staples_or_approves_release(self):
        self.app_status = "Invalid"
        with self.assertRaisesRegex(ValueError, "did not accept"):
            self.pipeline().execute()
        self.assertFalse(any("stapler" in command for command in self.commands))
        self.assertFalse((self.output / "SHA256SUMS.txt").exists())


if __name__ == "__main__":
    unittest.main()
