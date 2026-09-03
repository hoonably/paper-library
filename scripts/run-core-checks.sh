#!/bin/zsh
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

swiftc \
  -swift-version 5 \
  "$repository_root/Sources/PaperLibrary/Models/Paper.swift" \
  "$repository_root/Sources/PaperLibrary/Models/OrganizerStatus.swift" \
  "$repository_root/Sources/PaperLibrary/Services/CSVCodec.swift" \
  "$repository_root/Sources/PaperLibrary/Services/HTMLCatalogUpdater.swift" \
  "$repository_root/Sources/PaperLibrary/Services/IncomingPDFMover.swift" \
  "$repository_root/Tests/CoreChecks/main.swift" \
  -o "$temporary_directory/PaperLibraryCoreChecks"

"$temporary_directory/PaperLibraryCoreChecks"
