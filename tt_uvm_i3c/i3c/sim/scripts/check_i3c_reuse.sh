#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PORTABLE_DIR="$ROOT_DIR/verify/tb/portable/i3c"

[[ -d "$PORTABLE_DIR" ]] || {
    echo "[ERROR] Missing portable I3C tree: $PORTABLE_DIR" >&2
    exit 1
}

if grep -R -n -E --include='*.sv' --include='*.svh' \
    'axi4lite_base_seq|uvm_hdl_(force|read|release)' \
    "$PORTABLE_DIR/vseq/core" \
    "$PORTABLE_DIR/vseq/integration/portable"; then
    echo "[ERROR] Portable I3C vseqs contain parent-specific bus or HDL access" >&2
    exit 1
fi

echo "[PASS] Portable I3C vseqs use only the exported API/context boundary"
