#!/bin/zsh
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"

"$repository_root/scripts/run-core-checks.sh"
"$repository_root/scripts/build-local-app.sh"
"$repository_root/scripts/generate-appcast.sh" \
  "$repository_root/dist/Paper-Library.zip"

print "Release files are ready:"
print "  $repository_root/dist/Paper-Library.zip"
print "  $repository_root/appcast.xml"
