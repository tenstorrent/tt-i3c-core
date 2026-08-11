#!/usr/bin/env bash
# *****************************************************************************
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 VNCHIP LABS
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# File        : tt_local_env.sh
# Description : TT UVM I3C simulation support file.
# Authors     : Duy Huynh, Dang Thai
# Date        : 2026-08-11
#
# *****************************************************************************


# Standalone TT UVM I3C environment helper.
# Use:
#   source ./run.sh env
#
# Export I3C_ROOT_DIR before sourcing. The standalone package intentionally
# does not infer a host-specific location for the external RTL checkout.

_tt_package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
_tt_bundled_uvm_root="$_tt_package_root/third_party/uvm-core-2020.3.1"
_tt_selected_uvm_root="${DV_UVM_HOME:-${EXT_UVM_HOME:-${UVM_HOME:-}}}"

if [[ -z "$_tt_selected_uvm_root" ]] ||
   [[ ! -f "$_tt_selected_uvm_root/uvm_pkg.sv" &&
      ! -f "$_tt_selected_uvm_root/src/uvm_pkg.sv" ]]; then
    if [[ -n "$_tt_selected_uvm_root" ]]; then
        printf '[WARNING] Replacing unavailable UVM home: %s\n' \
            "$_tt_selected_uvm_root"
    fi
    _tt_selected_uvm_root="$_tt_bundled_uvm_root"
fi

export DV_UVM_HOME="$_tt_selected_uvm_root"
export EXT_UVM_HOME="$DV_UVM_HOME"

export DUT_MODE="${DUT_MODE:-rtl}"
export SOURCE_MODE="${SOURCE_MODE:-pinned}"
export I3C_SOURCE_LAYOUT="${I3C_SOURCE_LAYOUT:-auto}"

export I3C_ROOT_DIR="${I3C_ROOT_DIR:-}"
if [[ -z "$I3C_ROOT_DIR" ]]; then
    printf '[WARNING] I3C_ROOT_DIR is not set\n' >&2
    printf '[INFO] Export I3C_ROOT_DIR=/path/to/tt-i3c-core before running RTL flows\n'
fi

export CALIPTRA_ROOT="${CALIPTRA_ROOT:-}"
_tt_embedded_caliptra_root="${I3C_ROOT_DIR:+$I3C_ROOT_DIR/third_party/caliptra-rtl}"
if [[ -z "$CALIPTRA_ROOT" ]] ||
   [[ ! -f "$CALIPTRA_ROOT/src/caliptra_prim/rtl/caliptra_prim_pkg.sv" &&
      -n "$_tt_embedded_caliptra_root" &&
      -f "$_tt_embedded_caliptra_root/src/caliptra_prim/rtl/caliptra_prim_pkg.sv" ]]; then
    [[ -z "$CALIPTRA_ROOT" ]] ||
        printf '[WARNING] Replacing unavailable CALIPTRA_ROOT with the I3C core submodule\n' >&2
    export CALIPTRA_ROOT="$_tt_embedded_caliptra_root"
fi

printf '[INFO] Loaded standalone TT UVM I3C environment\n'
printf '[INFO] DV_UVM_HOME          : %s\n' "$DV_UVM_HOME"
printf '[INFO] I3C_SOURCE_LAYOUT    : %s\n' "$I3C_SOURCE_LAYOUT"
printf '[INFO] I3C_ROOT_DIR         : %s\n' "${I3C_ROOT_DIR:-(not set)}"
printf '[INFO] CALIPTRA_ROOT        : %s\n' "${CALIPTRA_ROOT:-(not set)}"

unset _tt_package_root _tt_bundled_uvm_root _tt_selected_uvm_root
unset _tt_embedded_caliptra_root
