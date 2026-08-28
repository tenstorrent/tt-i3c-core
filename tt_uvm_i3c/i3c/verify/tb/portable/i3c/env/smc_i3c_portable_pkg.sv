// *****************************************************************************
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 VNCHIP LABS
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// File        : smc_i3c_portable_pkg.sv
// Description : UVM package for I3C child.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-14
//
// *****************************************************************************

package smc_i3c_portable_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    `include "smc_i3c_portable_constants.sv"
    `include "smc_i3c_csr_api.sv"
    `include "smc_i3c_portable_services.sv"
    `include "smc_i3c_portable_context.sv"
    `include "smc_i3c_boundary_item.sv"
endpackage : smc_i3c_portable_pkg
