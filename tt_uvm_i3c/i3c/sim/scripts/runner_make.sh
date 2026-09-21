#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${DV_PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

exec make -C "$PROJECT_ROOT" -f "$SCRIPT_DIR/vcs_backend.mk" --no-print-directory "$@"
