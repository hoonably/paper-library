#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$PROJECT_ROOT/scripts/generate-appcast.py" "$@"
