#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$project_dir"
if [ ! -d desktop/node_modules ]; then
  (cd desktop && npm ci)
fi
if [ ! -f desktop/node_modules/electron/path.txt ]; then
  (cd desktop && node node_modules/electron/install.js)
fi
flutter build macos --release
node desktop/scripts/package-mac.cjs "$project_dir/build/macos/Build/Products/Release/vehicle_poster.app"
mkdir -p "$project_dir/build/nojoom"
app_target="$project_dir/build/nojoom/Nojoom Auction Posters.app"
rm -rf "$app_target"
ditto "$project_dir/build/macos/Build/Products/Release/vehicle_poster.app" "$app_target"
/usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string Nojoom Auction Posters' "$app_target/Contents/Info.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Nojoom Auction Posters' "$app_target/Contents/Info.plist"
codesign --force --deep --preserve-metadata=entitlements --sign - "$app_target"
codesign --verify --deep --strict "$app_target"
echo "Open: $app_target"
