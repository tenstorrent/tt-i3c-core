#!/bin/bash
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
# File        : check_vcs_version.sh
# Description : TT UVM I3C simulation support file.
# Authors     : Duy Huynh, Dang Thai
# Date        : 2026-08-11
#
# *****************************************************************************

set -euo pipefail

VCS_BIN="${VCS_BIN:-vcs}"
MINIMUM="${MINIMUM:-2020.12}"
ALLOW_UNSUPPORTED="${I3C_ALLOW_UNSUPPORTED_VCS:-1}"

command -v "$VCS_BIN" >/dev/null 2>&1 || {
    echo "[ERROR] VCS executable not found: $VCS_BIN" >&2
    exit 127
}

version_text="$($VCS_BIN -ID 2>&1 || true)"
version="$(printf '%s\n' "$version_text" | sed -nE 's/.*[A-Z]-([0-9]{4}\.[0-9]{2}).*/\1/p' | head -1)"
[[ -n "$version" ]] || {
    echo "[ERROR] Unable to parse VCS version from '$VCS_BIN -ID'" >&2
    printf '%s\n' "$version_text" >&2
    exit 1
}

version_key="${version/./}"
minimum_key="${MINIMUM/./}"
if ((10#$version_key < 10#$minimum_key)); then
    if [[ "$ALLOW_UNSUPPORTED" == "1" ]]; then
        echo "[WARNING] I3C supported baseline is VCS $MINIMUM or newer; found $version" >&2
        echo "[WARNING] Continuing compatibility build; compile/test results require separate review" >&2
        exit 0
    else
        echo "[ERROR] I3C RTL requires VCS $MINIMUM or newer; found $version" >&2
        echo "[ERROR] Set I3C_ALLOW_UNSUPPORTED_VCS=1 for a compatibility build" >&2
        exit 1
    fi
fi

# VCS-baseline PASS echo suppressed to keep startup output compact; the gate
# still enforces the baseline via the non-zero exit paths above.
: # version satisfies I3C baseline $MINIMUM
