#!/bin/zsh
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

swiftc \
  -swift-version 5 \
  "$repository_root/Sources/PaperLibrary/Models/Paper.swift" \
  "$repository_root/Sources/PaperLibrary/Models/CodexModelCatalog.swift" \
  "$repository_root/Sources/PaperLibrary/Models/OrganizerStatus.swift" \
  "$repository_root/Sources/PaperLibrary/Services/CSVCodec.swift" \
  "$repository_root/Sources/PaperLibrary/Services/IncomingPDFMover.swift" \
  "$repository_root/Sources/PaperLibrary/Services/LibraryLayout.swift" \
  "$repository_root/Sources/PaperLibrary/Services/PaperStorage.swift" \
  "$repository_root/Tests/CoreChecks/main.swift" \
  -o "$temporary_directory/PaperLibraryCoreChecks"

"$temporary_directory/PaperLibraryCoreChecks"

test_app="$temporary_directory/PaperLibraryAppLifecycleChecks.app"
mkdir -p "$test_app/Contents/MacOS"
cp "$repository_root/Tests/AppLifecycleChecks/Info.plist" "$test_app/Contents/Info.plist"

swiftc \
  -swift-version 5 -parse-as-library \
  "$repository_root/Sources/PaperLibrary/App/AppDelegate.swift" \
  "$repository_root/Tests/AppLifecycleChecks/main.swift" \
  -o "$test_app/Contents/MacOS/PaperLibraryAppLifecycleChecks"

"$test_app/Contents/MacOS/PaperLibraryAppLifecycleChecks"

node --test "$repository_root/Tests/ModelCatalogChecks/models.test.mjs"
node --test "$repository_root/Tests/FileMoveChecks/move.test.mjs"
