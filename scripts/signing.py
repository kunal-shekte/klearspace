#!/usr/bin/env python3
"""Developer ID preflight and signature checks. Does not access private-key bytes."""
import argparse
import os
import plistlib
import re
import subprocess
import sys


def run(args):
    result = subprocess.run([str(x) for x in args], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or f"Command failed: {args[0]}")
    return result


def resolve_identity(requested, team, listing):
    if not re.fullmatch(r"[A-Z0-9]{10}", team or ""):
        raise ValueError("Set KLEARSPACE_TEAM_ID to the intended publishing team's 10-character Team ID.")
    identities = re.findall(r'\b([A-Fa-f0-9]{40})\s+"([^"]+)"', listing)
    matches = [(sha, name) for sha, name in identities
               if name.startswith("Developer ID Application: ")
               and name.endswith(f"({team})")
               and (requested.upper() == sha.upper() or requested == name)]
    if len(matches) != 1:
        raise ValueError("No unique valid Developer ID Application identity matches the requested certificate and Team ID. Apple Development, Installer, and ad-hoc identities cannot notarize this app.")
    return matches[0][0]


def selected_identity():
    requested = os.environ.get("KLEARSPACE_SIGNING_IDENTITY", "")
    team = os.environ.get("KLEARSPACE_TEAM_ID", "")
    if not requested or requested == "-":
        raise ValueError("Set KLEARSPACE_SIGNING_IDENTITY to your Developer ID Application certificate name or SHA-1.")
    listing = run(["security", "find-identity", "-v", "-p", "codesigning"]).stdout
    return resolve_identity(requested, team, listing)


def validate_metadata(metadata, team, app, entitlements=None):
    if "Authority=Developer ID Application:" not in metadata:
        raise ValueError("The artifact is not signed with Developer ID Application.")
    if f"TeamIdentifier={team}\n" not in metadata + "\n":
        raise ValueError("The signature belongs to a different publishing team.")
    if "Timestamp=" not in metadata or "Timestamp=none" in metadata:
        raise ValueError("The signature has no secure timestamp.")
    if app and not re.search(r"flags=[^\n]*\bruntime\b", metadata):
        raise ValueError("The app does not enable the hardened runtime.")
    if app and (entitlements or {}).get("com.apple.security.get-task-allow", False):
        raise ValueError("Release signing must not enable get-task-allow.")


def verify(path, app=True):
    team = os.environ.get("KLEARSPACE_TEAM_ID", "")
    if not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise ValueError("KLEARSPACE_TEAM_ID is required to verify the publishing team.")
    run(["codesign", "--verify", "--deep", "--strict", path])
    result = run(["codesign", "--display", "--verbose=4", path])
    entitlements = {}
    if app:
        raw = run(["codesign", "--display", "--entitlements", "-", path]).stdout.strip()
        if raw:
            entitlements = plistlib.loads(raw.encode())
    validate_metadata(result.stderr + result.stdout, team, app, entitlements)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("identity")
    verify_parser = sub.add_parser("verify")
    verify_parser.add_argument("path")
    verify_parser.add_argument("--disk-image", action="store_true")
    args = parser.parse_args()
    try:
        if args.command == "identity":
            print(selected_identity())
        else:
            verify(args.path, app=not args.disk_image)
    except (RuntimeError, ValueError, plistlib.InvalidFileException) as error:
        print(f"Signing preflight: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
