#!/usr/bin/env python3
"""Resumable app + DMG notarization. Credentials stay in a named local Keychain profile."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

import signing

ROOT = Path(__file__).resolve().parents[1]


def command(args, capture=False):
    args = [str(x) for x in args]
    if capture:
        return signing.run(args).stdout
    subprocess.run(args, cwd=ROOT, check=True)
    return ""


def digest(path):
    with Path(path).open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest() if hasattr(hashlib, "file_digest") else _legacy_digest(source)


def _legacy_digest(source):
    value = hashlib.sha256()
    for chunk in iter(lambda: source.read(1024 * 1024), b""):
        value.update(chunk)
    return value.hexdigest()


def check_digest(path, expected):
    if not Path(path).is_file() or digest(path) != expected:
        raise ValueError(f"Artifact changed or disappeared after submission: {path}. Use a fresh output directory for a new build.")


def accepted_status(info):
    status = info.get("status")
    if status == "Accepted":
        return True
    if status == "In Progress":
        return False
    raise ValueError(f"Apple did not accept this submission (status: {status!r}). Review its notary log; no release was approved.")


class Pipeline:
    def __init__(self, output, profile):
        self.output = Path(output).resolve()
        self.profile = profile
        self.directory = self.output / ".notarization"
        self.state_file = self.directory / "state.json"
        self.state = json.loads(self.state_file.read_text()) if self.state_file.exists() else {}

    def save(self):
        self.directory.mkdir(parents=True, exist_ok=True)
        temporary = self.state_file.with_suffix(".tmp")
        temporary.write_text(json.dumps(self.state, indent=2) + "\n")
        temporary.replace(self.state_file)

    def notary(self, operation, *args):
        return json.loads(command(["xcrun", "notarytool", operation, *args, "--keychain-profile", self.profile, "--output-format", "json"], capture=True))

    def submission(self, stage, artifact):
        key = stage + "_id"
        if key not in self.state:
            # Record upload intent before requesting a new submission. An interrupted
            # request without a returned ID is never silently uploaded a second time.
            if self.state.get(stage + "_upload_started"):
                raise ValueError(f"The previous {stage} upload did not record an ID. Inspect notarytool history and use --recover-{stage}-id; do not resubmit blindly.")
            self.state[stage + "_upload_started"] = True
            self.save()
            result = self.notary("submit", artifact, "--no-wait")
            self.state[key] = result["id"]
            self.save()
        identifier = self.state[key]
        info = self.notary("info", identifier)
        if info.get("status") != "In Progress":
            command(["xcrun", "notarytool", "log", identifier, self.directory / (stage + "-log.json"), "--keychain-profile", self.profile])
        if not accepted_status(info):
            print(f"Apple is processing {stage} submission {identifier}. Rerun the same command later to resume without reuploading.")
            return False
        print(f"Apple accepted {stage} submission {identifier}.")
        return True

    def execute(self, recover_app=None, recover_dmg=None):
        identity = signing.selected_identity()
        team = os.environ["KLEARSPACE_TEAM_ID"]
        commit = command(["git", "-C", ROOT, "rev-parse", "HEAD"], capture=True).strip()
        if command(["git", "-C", ROOT, "status", "--porcelain", "--untracked-files=normal"], capture=True).strip():
            raise ValueError("Commit or stash source changes before creating a signed release.")
        config = {"identity": identity, "team": team, "profile": self.profile,
                  "commit": commit, "version": (ROOT / "VERSION").read_text().strip()}
        if self.state and self.state.get("config") != config:
            raise ValueError("Signing team, source commit, version, or profile changed. Start in a fresh output directory.")
        # Validate the profile before modifying build outputs. Only the profile name
        # is supplied; no password or API key is read by this script.
        self.notary("history")
        self.state["config"] = config
        self.save()
        for stage, identifier in [("app", recover_app), ("dmg", recover_dmg)]:
            if identifier:
                import uuid
                uuid.UUID(identifier)
                if not self.state.get(stage + "_upload_started") or self.state.get(stage + "_id"):
                    raise ValueError(f"No interrupted {stage} upload needs recovery.")
                if not self.state.get(stage + "_sha256"):
                    raise ValueError(f"No recorded {stage} payload is available to recover.")
                self.state[stage + "_id"] = identifier
                self.save()

        app = self.output / "Klearspace.app"
        archive = self.directory / "Klearspace-notarization.zip"
        os.environ["KLEARSPACE_OUTPUT_DIR"] = str(self.output)
        if "app_sha256" not in self.state:
            command([ROOT / "build.sh"])
            signing.verify(app)
            command(["ditto", "-c", "-k", "--keepParent", app, archive])
            self.state["app_sha256"] = digest(archive)
            self.save()
        check_digest(archive, self.state["app_sha256"])
        # Always restore the exact submitted app, rather than trusting an output
        # bundle that may have been rebuilt while Apple's response was pending.
        with tempfile.TemporaryDirectory(prefix="app-", dir=self.directory) as staging:
            command(["ditto", "-x", "-k", archive, staging])
            candidate = Path(staging) / "Klearspace.app"
            signing.verify(candidate)
            if not self.submission("app", archive):
                return 2
            command(["xcrun", "stapler", "staple", candidate])
            command(["xcrun", "stapler", "validate", candidate])
            command(["spctl", "--assess", "--type", "execute", "--verbose=2", candidate])
            if app.is_symlink() or app.is_file():
                app.unlink()
            elif app.exists():
                shutil.rmtree(app)
            candidate.replace(app)

        if "dmg_sha256" not in self.state:
            command([ROOT / "scripts/package-dmg.sh"])
            checksum = self.output / "SHA256SUMS.txt"
            if checksum.exists():
                checksum.replace(self.directory / "pre-notarization-checksum.txt")
            architecture = command(["lipo", "-archs", app / "Contents/MacOS/Klearspace"], capture=True).strip()
            if architecture not in ("arm64", "x86_64"):
                architecture = "universal"
            dmg = self.output / f"Klearspace-{config['version']}-{architecture}.dmg"
            self.state["dmg_name"] = dmg.name
            self.state["dmg_sha256"] = digest(dmg)
            shutil.copyfile(dmg, self.directory / ("submitted-" + dmg.name))
            self.save()
        name = self.state["dmg_name"]
        if Path(name).name != name or not name.startswith("Klearspace-") or not name.endswith(".dmg"):
            raise ValueError("The saved DMG filename is invalid.")
        dmg = self.output / name
        submitted_dmg = self.directory / ("submitted-" + name)
        check_digest(submitted_dmg, self.state["dmg_sha256"])
        if self.state.get("ready_sha256"):
            check_digest(dmg, self.state["ready_sha256"])
        if not self.submission("dmg", submitted_dmg):
            return 2
        # Stapling changes DMG bytes. Retain the immutable submitted payload and
        # work on a disposable copy so any interruption can safely retry locally.
        with tempfile.TemporaryDirectory(prefix="dmg-", dir=self.directory) as staging:
            candidate = Path(staging) / name
            shutil.copyfile(submitted_dmg, candidate)
            command(["xcrun", "stapler", "staple", candidate])
            command(["xcrun", "stapler", "validate", candidate])
            signing.verify(candidate, app=False)
            command(["spctl", "--assess", "--type", "open", "--context", "context:primary-signature", "--verbose=2", candidate])
            command(["hdiutil", "verify", candidate])
            final_hash = digest(candidate)
            candidate.replace(dmg)
        self.state["ready_sha256"] = final_hash
        self.save()
        checksum = self.output / "SHA256SUMS.txt"
        temporary = self.directory / "final-checksum.txt"
        temporary.write_text(f"{final_hash}  {dmg.name}\n")
        temporary.replace(checksum)
        print(f"Notarized and stapled app + DMG verified: {dmg}")
        print("Checksums reflect the final stapled DMG. No GitHub release was changed.")
        return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", default=os.environ.get("KLEARSPACE_NOTARY_PROFILE"))
    parser.add_argument("--output", default=os.environ.get("KLEARSPACE_OUTPUT_DIR", str(ROOT / "dist")))
    parser.add_argument("--recover-app-id")
    parser.add_argument("--recover-dmg-id")
    args = parser.parse_args()
    if not args.profile:
        parser.error("Use --profile to name your own notarization Keychain profile.")
    try:
        return Pipeline(args.output, args.profile).execute(args.recover_app_id, args.recover_dmg_id)
    except (RuntimeError, ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Notarization stopped: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
