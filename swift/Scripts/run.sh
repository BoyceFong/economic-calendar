#!/bin/bash
# Dev run (bare executable, no .app): notifications and login items are
# disabled in this mode; data lives in <repo>/data next to the Python app.
#
# Usage: swift/Scripts/run.sh [--print-cache | --fetch-once | ...]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

cd "$REPO_ROOT"
exec swift run --package-path "$REPO_ROOT/swift" -c debug EconomicCalendar "$@"
