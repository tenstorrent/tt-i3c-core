#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

BLACKBOX_VSEQ_DIRS=(
  "${ROOT_DIR}/verify/tb/vseq/core"
)

forbidden_pattern='get_ral_model_handle|ral_model\.|uvm_hdl_|DUT_HDL_PATH|TB_TOP_HDL_PATH'
found_forbidden=0

for vseq_dir in "${BLACKBOX_VSEQ_DIRS[@]}"; do
  if [[ ! -d "${vseq_dir}" ]]; then
    continue
  fi
  if grep -RInE "${forbidden_pattern}" "${vseq_dir}" --include='*.sv'; then
    found_forbidden=1
  fi
done

if [[ "${found_forbidden}" -ne 0 ]]; then
  echo "ERROR: blackbox-safe vseq dirs must remain API-only." >&2
  echo "       Move direct RAL/HDL usage to integration or IP-only vseqs." >&2
  exit 1
fi

echo "PASS: blackbox-safe vseq dirs have no direct RAL/HDL dependency."
