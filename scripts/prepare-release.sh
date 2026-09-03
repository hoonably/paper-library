#!/bin/zsh
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
release_notes="${1:-}"

"$repository_root/scripts/run-core-checks.sh"
"$repository_root/scripts/build-local-app.sh"

if [[ -n "$release_notes" ]]; then
  "$repository_root/scripts/generate-appcast.sh" \
    "$repository_root/dist/Paper-Library.zip" \
    "$release_notes"
else
  "$repository_root/scripts/generate-appcast.sh" \
    "$repository_root/dist/Paper-Library.zip"
fi

print "Release files are ready:"
print "  $repository_root/dist/Paper-Library.zip"
print "  $repository_root/appcast.xml"
