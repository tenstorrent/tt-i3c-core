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
// File        : axi4lite_vip_pkg.sv
// Description : UVM package for the AXI4-Lite master VIP.
// Authors     : Dang Thai
// Date        : 2026-07-28
//
// *****************************************************************************

`ifndef AXI4LITE_VIP_PKG_SV
`define AXI4LITE_VIP_PKG_SV

package axi4lite_vip_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  `include "core/axi4lite_config.sv"
  `include "core/axi4lite_item.sv"
  `include "agent/axi4lite_sequencer.sv"
  `include "agent/axi4lite_driver.sv"
  `include "agent/axi4lite_monitor.sv"
  `include "agent/axi4lite_agent.sv"
  `include "sequences/axi4lite_base_seq.sv"
endpackage : axi4lite_vip_pkg

`endif // AXI4LITE_VIP_PKG_SV
