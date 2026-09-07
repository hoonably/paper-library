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
sparkle_framework="$app_bundle/Contents/Frameworks/Sparkle.framework"

if [[ "$bundle_id" == *'$('* || "$version" == *'$('* || "$build_number" == *'$('* ]]; then
  print -u2 "The app contains unresolved build-setting placeholders."
  exit 65
fi

codesign --verify --deep --strict --verbose=2 "$app_bundle"
if [[ ! -d "$sparkle_framework" ]]; then
  print -u2 "The app is missing Sparkle.framework."
  exit 65
fi

feed_url="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$plist")"
public_update_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$plist")"
requires_signed_feed="$(/usr/libexec/PlistBuddy -c 'Print :SURequireSignedFeed' "$plist")"
verifies_before_extraction="$(/usr/libexec/PlistBuddy -c 'Print :SUVerifyUpdateBeforeExtraction' "$plist")"
if [[ "$feed_url" != https://* || -z "$public_update_key" ||
      "$requires_signed_feed" != "true" || "$verifies_before_extraction" != "true" ]]; then
  print -u2 "The app does not contain a secure Sparkle update configuration."
  exit 65
fi

signature_details="$(codesign -dv --verbose=4 "$app_bundle" 2>&1)"
if ! print -r -- "$signature_details" | grep -q '^Authority=Developer ID Application:'; then
  print -u2 "The app is not signed with a Developer ID Application certificate."
  exit 65
fi

entitlements="$(mktemp)"
trap 'rm -f "$entitlements"' EXIT
if codesign -d --entitlements :- "$app_bundle" > "$entitlements" 2>/dev/null &&
   [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$entitlements" 2>/dev/null || true)" == "true" ]]; then
  print -u2 "The app is sandboxed and cannot manage its shared Application Support storage."
  exit 65
fi

service_name="$(/usr/libexec/PlistBuddy -c 'Print :NSServices:0:NSMenuItem:default' "$plist")"
if [[ "$service_name" != "Move to Paper Library" ]]; then
  print -u2 "The Finder service declaration is missing or unexpected."
  exit 65
fi

for bundled_resource in \
  "LibrarySeed/Automation/PAPER_LIBRARY_EDITOR.md" \
  "LibrarySeed/Automation/PAPER_ORGANIZER.md" \
  "LibrarySeed/Automation/library-command-schema.json" \
  "LibrarySeed/Automation/paper-organizer.mjs"; do
  if [[ ! -f "$app_bundle/Contents/Resources/$bundled_resource" ]]; then
    print -u2 "The app is missing $bundled_resource."
    exit 65
  fi
done

if find "$app_bundle/Contents" -type f \( \
  -name 'papers.csv' -o \
  -name 'organizer-settings.json' -o \
  -name 'runtime-status.json' -o \
  -name 'processing-papers.json' -o \
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
