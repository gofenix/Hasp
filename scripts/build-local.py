#!/usr/bin/env python3
"""Build Hasp with the Apple developer account configured in Xcode."""

import argparse
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def run(arguments):
    subprocess.run([str(value) for value in arguments], cwd=ROOT, check=True)


def cached_development_team():
    """Read public team metadata for accounts currently registered in Xcode."""
    preferences = Path.home() / "Library/Preferences"
    try:
        accounts = plistlib.loads((preferences / "com.apple.dt.Xcode.plist").read_bytes())
        cache = plistlib.loads((preferences / "com.apple.dt.xcodebuild.plist").read_bytes())
    except (OSError, plistlib.InvalidFileException):
        return None
    identifiers = {
        account.get("identifier")
        for account in accounts.get("DVTDeveloperAccountManagerAppleIDLists", {}).get("IDE.Identifiers.Prod", [])
    }
    teams = {
        team["teamID"]
        for identifier, entries in cache.get("IDEProvisioningTeamByIdentifier", {}).items()
        if identifier in identifiers
        for team in entries
        if isinstance(team, dict) and re.fullmatch(r"[A-Z0-9]{10}", team.get("teamID", ""))
    }
    return next(iter(teams)) if len(teams) == 1 else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--team", default=os.environ.get("HASP_DEVELOPMENT_TEAM"), help="Apple developer Team ID")
    parser.add_argument("--configuration", choices=["Debug", "Release"], default="Debug", help="Release enables compiler optimizations; both use the same Apple signing identity")
    options = parser.parse_args()
    project = (ROOT / "Hasp.xcodeproj/project.pbxproj").read_text()
    configured = re.search(r'DEVELOPMENT_TEAM\s*=\s*"?([A-Z0-9]{10})"?;', project)
    team = options.team or (configured.group(1) if configured else cached_development_team())
    if team is None or not re.fullmatch(r"[A-Z0-9]{10}", team):
        sys.exit("Sign in to Xcode Accounts, then provide your Team ID with --team or HASP_DEVELOPMENT_TEAM.")
    run([
        "xcodebuild", "-project", "Hasp.xcodeproj", "-scheme", "Hasp",
        "-configuration", options.configuration, "-destination", "platform=macOS",
        "-derivedDataPath", "build", "-allowProvisioningUpdates", "build",
        "CODE_SIGN_STYLE=Automatic", "CODE_SIGN_IDENTITY=Apple Development", f"DEVELOPMENT_TEAM={team}",
    ])
    app = ROOT / f"build/Build/Products/{options.configuration}/Hasp.app"
    run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", app])
    run(["codesign", "--display", "--requirements", "-", app])
    print(f"Signed local build: {app}")
    print("Quit Hasp before replacing /Applications/Hasp.app with this build.")


if __name__ == "__main__":
    main()
