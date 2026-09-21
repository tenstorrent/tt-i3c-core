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
// File        : i3c_ibi_controller_rx_timing_context_test.sv
// Description : UVM test for I3C IBI controller timing context.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-28
//
// *****************************************************************************

`ifndef I3C_IBI_CONTROLLER_RX_TIMING_CONTEXT_TEST_SV
`define I3C_IBI_CONTROLLER_RX_TIMING_CONTEXT_TEST_SV

class i3c_ibi_controller_rx_timing_context_test extends
    i3c_ibi_controller_rx_basic_test;
  `uvm_component_utils(i3c_ibi_controller_rx_timing_context_test)

  function new(string name = "i3c_ibi_controller_rx_timing_context_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    string context_arg;

    super.build_phase(phase);
    cfg.ibi_timing_context = 3;
    if ($value$plusargs("IBI_TIMING_CONTEXT=%s", context_arg)) begin
      case (context_arg)
        "IDLE", "idle":
          cfg.ibi_timing_context = 0;
        "AFTER_XFER", "after_xfer":
          cfg.ibi_timing_context = 1;
        "BUSY_DEFER", "busy_defer":
          cfg.ibi_timing_context = 2;
        "ALL", "all":
          cfg.ibi_timing_context = 3;
        default:
          `uvm_fatal("IBI_TIMING_CONTEXT",
                     $sformatf("Unsupported IBI_TIMING_CONTEXT=%s",
                               context_arg))
      endcase
    end
  endfunction

  virtual function i3c_base_vseq create_vseq();
    return i3c_ibi_controller_rx_timing_context_vseq::type_id::create(
      "vseq");
  endfunction
endclass : i3c_ibi_controller_rx_timing_context_test

`endif // I3C_IBI_CONTROLLER_RX_TIMING_CONTEXT_TEST_SV
