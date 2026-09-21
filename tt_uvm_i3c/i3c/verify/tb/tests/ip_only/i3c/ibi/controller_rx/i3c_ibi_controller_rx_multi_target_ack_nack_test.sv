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
// File        : i3c_ibi_controller_rx_multi_target_ack_nack_test.sv
// Description : DUT-Controller multi-requester ACK/NACK policy test.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-09-08
//
// *****************************************************************************
`ifndef I3C_IBI_CONTROLLER_RX_MULTI_TARGET_ACK_NACK_TEST_SV
`define I3C_IBI_CONTROLLER_RX_MULTI_TARGET_ACK_NACK_TEST_SV

class i3c_ibi_controller_rx_multi_target_ack_nack_test extends i3c_ibi_controller_rx_multi_target_test;
  `uvm_component_utils(i3c_ibi_controller_rx_multi_target_ack_nack_test)
  function new(string name = "i3c_ibi_controller_rx_multi_target_ack_nack_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  virtual function i3c_base_vseq create_vseq();
    return i3c_ibi_controller_rx_multi_target_ack_nack_vseq::type_id::create("vseq");
  endfunction
endclass

`endif
