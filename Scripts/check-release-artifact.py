#!/usr/bin/env python3
"""Inspect a local Xcode archive; this is not App Store server validation."""
import argparse
import json
import plistlib
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("archive", type=Path)
args = parser.parse_args()
archive = args.archive.resolve()
info = plistlib.loads((archive / "Info.plist").read_bytes())
app = archive / "Products" / info["ApplicationProperties"]["ApplicationPath"]
bundle = plistlib.loads((app / "Info.plist").read_bytes())
privacy = plistlib.loads((app / "PrivacyInfo.xcprivacy").read_bytes())
checks = {
    "bundle_identifier": bundle.get("CFBundleIdentifier") == "com.bookslibrary.polka",
    "version": bundle.get("CFBundleShortVersionString") == "1.0.0",
    "build": bundle.get("CFBundleVersion") == "12",
    "display_name": bundle.get("CFBundleDisplayName") == "Bookreign",
    "iphone_and_ipad": set(bundle.get("UIDeviceFamily", [])) == {1, 2},
    "system_encryption_declaration": bundle.get("ITSAppUsesNonExemptEncryption") is False,
    "camera_purpose": bool(bundle.get("NSCameraUsageDescription")),
    "no_tracking": privacy.get("NSPrivacyTracking") is False,
    "user_defaults_reason": any(
        item.get("NSPrivacyAccessedAPIType") == "NSPrivacyAccessedAPICategoryUserDefaults"
        and "CA92.1" in item.get("NSPrivacyAccessedAPITypeReasons", [])
        for item in privacy.get("NSPrivacyAccessedAPITypes", [])
    ),
    "localized_system_strings": all((app / f"{locale}.lproj" / "InfoPlist.strings").is_file() for locale in ("uk", "en", "ru")),
    "dSYM": (archive / "dSYMs" / "Polka.app.dSYM").is_dir(),
    "no_ui_test_bundle": not any(app.rglob("*.xctest")),
}
for name in ("Library", "Catalog", "Settings", "Errors", "Topics", "Covers", "ScanFlow", "Privacy"):
    matches = list(app.rglob(name + ".json"))
    checks["localization_" + name] = len(matches) == 1
    if len(matches) == 1:
        values = json.loads(matches[0].read_text())
        checks["translations_" + name] = all(all(entry.get(locale) for locale in ("uk", "en", "ru")) for entry in values.values())
signature = subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], capture_output=True, text=True)
checks["code_signature"] = signature.returncode == 0
for name, valid in checks.items():
    print(f"{'PASS' if valid else 'FAIL'} {name}")
print(f"{sum(checks.values())}/{len(checks)} local artifact checks passed.")
print("Account setup, public URLs, privacy labels, provider permissions and Apple validation remain separate release gates.")
raise SystemExit(0 if all(checks.values()) else 1)
