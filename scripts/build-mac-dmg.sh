#!/bin/zsh
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$(uname -s)" != Darwin ]]; then
  print -u2 "DMG packaging requires macOS."
  exit 1
fi
exec "${UV_BIN:-uv}" run --no-project \
  --with 'dmgbuild==1.6.7' --with 'ds-store==1.3.3' --with 'mac-alias==2.2.3' \
  python "$repository_root/scripts/build-dmg.py" \
  "${1:-$repository_root/dist/Paper Library.app}" "${2:-$repository_root/dist}"
