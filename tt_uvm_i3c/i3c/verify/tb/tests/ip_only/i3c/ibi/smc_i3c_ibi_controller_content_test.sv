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
// File        : smc_i3c_ibi_controller_content_test.sv
// Description : UVM test for I3C IBI controller content.
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-25
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_CONTROLLER_CONTENT_TEST_SV
`define SMC_I3C_IBI_CONTROLLER_CONTENT_TEST_SV

// DUT-controller content test. A Device-mode UVM target sends one accepted
// IBI containing MDB A5 and payload 11 22 33 44. The inherited Controller
// pipeline checks ACK, HCI descriptor fields, byte-accurate two-DWORD content,
// FIFO/IRQ behavior and functional-coverage sampling.
class smc_i3c_ibi_controller_content_test extends
    smc_i3c_ibi_controller_receive_test;
  `uvm_component_utils(smc_i3c_ibi_controller_content_test)

  function new(string name = "smc_i3c_ibi_controller_content_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function smc_peripherals_base_vseq create_vseq();
    return smc_i3c_ibi_controller_content_vseq::type_id::create("vseq");
  endfunction
endclass : smc_i3c_ibi_controller_content_test

`endif // SMC_I3C_IBI_CONTROLLER_CONTENT_TEST_SV
