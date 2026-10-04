#!/bin/bash
# Prepare a local archive and App Store IPA; never uploads or submits the app.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
release_root="${1:-$project_root/Release}"
archive_path="$release_root/Bookreign-1.0.0-12.xcarchive"
mkdir -p "$release_root"
cd "$project_root"
if [[ -e "$archive_path" ]]; then
  echo "Archive already exists: $archive_path. Choose a different output directory to preserve it."
  exit 1
fi
python3 Scripts/check-localizations.py
xcodebuild -project Polka.xcodeproj -scheme Polka -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$archive_path" \
  -derivedDataPath "$release_root/DerivedData" -allowProvisioningUpdates archive
python3 Scripts/check-release-artifact.py "$archive_path"
xcodebuild -exportArchive -archivePath "$archive_path" \
  -exportOptionsPlist docs/app-store/ExportOptions.plist \
  -exportPath "$release_root/AppStoreExport" -allowProvisioningUpdates
