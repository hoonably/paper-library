#!/bin/zsh
set -euo pipefail

if (( $# != 1 )); then
  print -u2 "Usage: scripts/verify-release-app.sh '/path/to/Paper Library.app'"
  exit 64
fi

app_bundle="${1:A}"
plist="$app_bundle/Contents/Info.plist"

if [[ ! -d "$app_bundle" || ! -f "$plist" ]]; then
  print -u2 "Not a macOS app bundle: $app_bundle"
  exit 66
fi

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")"
executable="$app_bundle/Contents/MacOS/$executable_name"

if [[ "$bundle_id" == *'$('* || "$version" == *'$('* || "$build_number" == *'$('* ]]; then
  print -u2 "The app contains unresolved build-setting placeholders."
  exit 65
fi

codesign --verify --deep --strict --verbose=2 "$app_bundle"
signature_details="$(codesign -dv --verbose=4 "$app_bundle" 2>&1)"
if ! print -r -- "$signature_details" | grep -q '^Authority=Developer ID Application:'; then
  print -u2 "The app is not signed with a Developer ID Application certificate."
  exit 65
fi

entitlements="$(mktemp)"
trap 'rm -f "$entitlements"' EXIT
codesign -d --entitlements :- "$app_bundle" > "$entitlements" 2>/dev/null
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$entitlements")" != "true" ]]; then
  print -u2 "The App Sandbox entitlement is missing."
  exit 65
fi
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.files.bookmarks.app-scope' "$entitlements")" != "true" ]]; then
  print -u2 "The app-scoped bookmark entitlement is missing."
  exit 65
fi
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.files.user-selected.read-write' "$entitlements")" != "true" ]]; then
  print -u2 "The user-selected read/write entitlement is missing."
  exit 65
fi

service_name="$(/usr/libexec/PlistBuddy -c 'Print :NSServices:0:NSMenuItem:default' "$plist")"
if [[ "$service_name" != "Move to Paper Library" ]]; then
  print -u2 "The Finder service declaration is missing or unexpected."
  exit 65
fi

if find "$app_bundle/Contents" -type f \( \
  -name 'papers.csv' -o \
  -name 'organizer-settings.json' -o \
  -name 'runtime-status.js' -o \
  -name 'papers.html' \
\) -print -quit | grep -q .; then
  print -u2 "Private library data was packaged inside the app."
  exit 65
fi

architectures="$(lipo -archs "$executable")"
for required_architecture in arm64 x86_64; do
  if [[ " $architectures " != *" $required_architecture "* ]]; then
    print -u2 "The release executable is not universal; missing $required_architecture."
    exit 65
  fi
done

xcrun stapler validate "$app_bundle"
spctl --assess --type execute --verbose=4 "$app_bundle"

print "Release app verified"
print "  Bundle: $bundle_id"
print "  Version: $version ($build_number)"
print "  Architectures: $architectures"
print "  Signing: Developer ID"
print "  Notarization ticket: stapled"
