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
  "$repository_root/Tests/CoreChecks/main.swift" \
  -o "$temporary_directory/PaperLibraryCoreChecks"

"$temporary_directory/PaperLibraryCoreChecks"

swiftc \
  -swift-version 5 -parse-as-library \
  "$repository_root/Sources/PaperLibrary/App/AppDelegate.swift" \
  "$repository_root/Tests/AppLifecycleChecks/main.swift" \
  -o "$temporary_directory/PaperLibraryAppLifecycleChecks"

"$temporary_directory/PaperLibraryAppLifecycleChecks"

node --test "$repository_root/Tests/ModelCatalogChecks/models.test.mjs"
