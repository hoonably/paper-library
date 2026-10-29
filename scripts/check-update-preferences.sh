#!/bin/zsh
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT
framework_directory="$repository_root/.build/arm64-apple-macosx/debug"
if [[ ! -d "$framework_directory/Sparkle.framework" ]]; then
  framework_directory="$repository_root/.build/x86_64-apple-macosx/debug"
fi
if [[ ! -d "$framework_directory/Sparkle.framework" ]]; then
  print -u2 "Run swift build --disable-keychain before this check."
  exit 1
fi
test_app="$temporary_directory/UpdateChecks.app"
mkdir -p "$test_app/Contents/MacOS"
cat > "$test_app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.hoonably.PaperLibrary.UpdateChecks.$(uuidgen)</string>
<key>CFBundleExecutable</key><string>UpdateChecks</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSBackgroundOnly</key><true/>
<key>SUEnableAutomaticChecks</key><true/>
<key>SUAutomaticallyUpdate</key><false/>
</dict></plist>
PLIST
swiftc -swift-version 5 -parse-as-library \
  -F "$framework_directory" -framework Sparkle \
  -Xlinker -rpath -Xlinker "$framework_directory" \
  "$repository_root/Sources/PaperLibrary/App/UpdateController.swift" \
  "$repository_root/Tests/UpdatePreferencesChecks/main.swift" \
  -o "$test_app/Contents/MacOS/UpdateChecks"
"$test_app/Contents/MacOS/UpdateChecks" disable
"$test_app/Contents/MacOS/UpdateChecks" relaunch
