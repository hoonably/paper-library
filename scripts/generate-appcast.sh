#!/bin/zsh
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
archive="${1:-$repository_root/dist/Paper-Library.zip}"
release_notes="${2:-}"
private_key_file="${SPARKLE_PRIVATE_KEY_FILE:-$HOME/Library/Application Support/Paper Library Development/sparkle-private-key}"
appcast_output="${APPCAST_OUTPUT:-$repository_root/appcast.xml}"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

if [[ ! -f "$archive" ]]; then
  print -u2 "Update archive not found: $archive"
  exit 66
fi

if [[ ! -f "$private_key_file" ]]; then
  print -u2 "Sparkle private key not found: $private_key_file"
  print -u2 "Restore the release key before generating an update."
  exit 66
fi

cd "$repository_root"
swift package resolve --disable-keychain

generate_appcast="$(find "$repository_root/.build/artifacts" -path '*/Sparkle/bin/generate_appcast' -type f -print -quit)"
if [[ -z "$generate_appcast" ]]; then
  print -u2 "Sparkle release tools could not be located."
  exit 69
fi

public_key="$(swift -e '
import CryptoKit
import Foundation

let path = CommandLine.arguments[1]
let encodedKey = try String(contentsOfFile: path, encoding: .utf8)
    .trimmingCharacters(in: .whitespacesAndNewlines)
guard let seed = Data(base64Encoded: encodedKey) else {
    fatalError("The Sparkle private key is not valid Base64.")
}
let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
print(key.publicKey.rawRepresentation.base64EncodedString())
' "$private_key_file")"
embedded_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' PaperLibrary/Info.plist)"
if [[ "$public_key" != "$embedded_key" ]]; then
  print -u2 "The Sparkle signing key does not match the public key embedded in the app."
  exit 65
fi

extracted_directory="$temporary_directory/extracted"
updates_directory="$temporary_directory/updates"
mkdir -p "$extracted_directory" "$updates_directory"
ditto -x -k "$archive" "$extracted_directory"
app_bundle="$(find "$extracted_directory" -maxdepth 1 -type d -name '*.app' -print -quit)"
if [[ -z "$app_bundle" ]]; then
  print -u2 "The archive does not contain an app bundle."
  exit 65
fi

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_bundle/Contents/Info.plist")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_bundle/Contents/Info.plist")"
cp "$archive" "$updates_directory/Paper-Library.zip"
cp "$appcast_output" "$updates_directory/appcast.xml"
if [[ -n "$release_notes" ]]; then
  if [[ ! -f "$release_notes" ]]; then
    print -u2 "Release notes not found: $release_notes"
    exit 66
  fi
  cp "$release_notes" "$updates_directory/Paper-Library.md"
fi

"$generate_appcast" \
  --ed-key-file "$private_key_file" \
  --download-url-prefix "https://github.com/hoonably/paper-library/releases/download/v$version/" \
  --release-notes-url-prefix "https://github.com/hoonably/paper-library/releases/download/v$version/" \
  --link "https://github.com/hoonably/paper-library/releases/tag/v$version" \
  --maximum-versions 5 \
  --maximum-deltas 0 \
  -o "$updates_directory/appcast.xml" \
  "$updates_directory"

if [[ -n "$release_notes" ]]; then
  cp "$updates_directory/Paper-Library.md" "$release_notes"
fi

xmllint --noout "$updates_directory/appcast.xml"
if ! grep -q "<sparkle:version>$build_number</sparkle:version>" "$updates_directory/appcast.xml" ||
   ! grep -q 'sparkle:edSignature=' "$updates_directory/appcast.xml" ||
   ! grep -q '<!-- sparkle-signatures:' "$updates_directory/appcast.xml"; then
  print -u2 "The generated appcast is missing the expected version or EdDSA signatures."
  exit 65
fi

cp "$updates_directory/appcast.xml" "$appcast_output"
print "Updated $appcast_output for Paper Library $version ($build_number)"
