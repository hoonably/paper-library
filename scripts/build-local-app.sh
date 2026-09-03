#!/bin/zsh
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
destination_root="${1:-$repository_root/dist}"
app_bundle="$destination_root/Paper Library.app"
zip_path="$destination_root/Paper-Library.zip"
temporary_directory="$(mktemp -d)"
staged_app="$temporary_directory/Paper Library.app"
staged_zip="$temporary_directory/Paper-Library.zip"
scratch_directory="$temporary_directory/swift-build"
trap 'rm -rf "$temporary_directory"' EXIT

cd "$repository_root"
swift build -c release --scratch-path "$scratch_directory"

mkdir -p "$destination_root"
rm -rf "$app_bundle"
rm -f "$zip_path"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"

cp "$scratch_directory/release/PaperLibrary" "$staged_app/Contents/MacOS/PaperLibrary"
cp "PaperLibrary/Info.plist" "$staged_app/Contents/Info.plist"
ditto "Sources/PaperLibrary/Resources/LibrarySeed" "$staged_app/Contents/Resources/LibrarySeed"

/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable PaperLibrary" "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_ID:-com.hoonably.PaperLibrary}" "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Paper Library" "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${APP_VERSION:-0.2.0}" "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER:-2}" "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion 14.0" "$staged_app/Contents/Info.plist"

iconset="$temporary_directory/AppIcon.iconset"
icon_source="PaperLibrary/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png"
mkdir -p "$iconset"
sips -z 16 16 "$icon_source" --out "$iconset/icon_16x16.png" >/dev/null
sips -z 32 32 "$icon_source" --out "$iconset/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$icon_source" --out "$iconset/icon_32x32.png" >/dev/null
sips -z 64 64 "$icon_source" --out "$iconset/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$icon_source" --out "$iconset/icon_128x128.png" >/dev/null
sips -z 256 256 "$icon_source" --out "$iconset/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$icon_source" --out "$iconset/icon_256x256.png" >/dev/null
sips -z 512 512 "$icon_source" --out "$iconset/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$icon_source" --out "$iconset/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$icon_source" --out "$iconset/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$iconset" -o "$staged_app/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$staged_app/Contents/Info.plist"
xattr -cr "$staged_app"

if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime \
    --entitlements "PaperLibrary/PaperLibrary.entitlements" \
    --sign "$CODE_SIGN_IDENTITY" "$staged_app"
else
  codesign --force --deep \
    --entitlements "PaperLibrary/PaperLibrary.entitlements" \
    --sign - "$staged_app"
fi

codesign --verify --deep --strict --verbose=2 "$staged_app"
ditto -c -k --sequesterRsrc --keepParent "$staged_app" "$staged_zip"
cp "$staged_zip" "$zip_path"

ditto --norsrc "$staged_app" "$app_bundle"
xattr -cr "$app_bundle" || true
# Some File Provider-backed folders attach Finder metadata shortly after a
# bundle appears. Verify again after that window and keep only the ZIP if the
# destination changed the signed app.
sleep 1
if codesign --verify --deep --strict --verbose=2 "$app_bundle" 2>/dev/null; then
  print "Built and verified $app_bundle"
else
  rm -rf "$app_bundle"
  print "Skipped the loose app because the destination modified its signature; use the verified ZIP instead"
fi
print "Created verified archive $zip_path"
