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
// File        : i3c_ibi_controller_rx_content_test.sv
// Description : UVM test for I3C IBI controller content.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-25
//
// *****************************************************************************

`ifndef I3C_IBI_CONTROLLER_RX_CONTENT_TEST_SV
`define I3C_IBI_CONTROLLER_RX_CONTENT_TEST_SV

// DUT-controller content test. A Device-mode UVM target sends one accepted
// IBI containing MDB A5 and a deterministic payload selected with
// +IBI_CONTENT_PAYLOAD_LEN. The inherited Controller pipeline checks ACK, HCI
// descriptor fields, byte-accurate content, FIFO/IRQ behavior and coverage.
class i3c_ibi_controller_rx_content_test extends
    i3c_ibi_controller_rx_basic_test;
  `uvm_component_utils(i3c_ibi_controller_rx_content_test)

  function new(string name = "i3c_ibi_controller_rx_content_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function i3c_base_vseq create_vseq();
    return i3c_ibi_controller_rx_content_vseq::type_id::create("vseq");
  endfunction
endclass : i3c_ibi_controller_rx_content_test

`endif // I3C_IBI_CONTROLLER_RX_CONTENT_TEST_SV
